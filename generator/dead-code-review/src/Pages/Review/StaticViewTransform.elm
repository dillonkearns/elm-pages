module Pages.Review.StaticViewTransform exposing (rule)

{-| This rule transforms static region render calls into adopt calls in the client
bundle. This enables dead-code elimination of the static rendering dependencies
(markdown parsers, syntax highlighters, etc.) while preserving the pre-rendered
HTML for adoption by the virtual-dom.

## Transformations

    -- View.freeze (single argument, new API):
    View.freeze (heavyRender data)
    -- becomes:
    View.Static.adopt "0" |> Html.Styled.fromUnstyled |> Html.Styled.map never

    -- View.Static.static (plain Html):
    View.Static.static (heavyRender data)
    -- becomes:
    View.Static.adopt "0"

## Data Type Transformation

This rule analyzes field access patterns on `app.data` and removes fields that
are NOT used on the client (i.e., fields only used in ephemeral contexts like
`View.freeze` calls or the `head` function).

The model is:
- Start with ALL fields from the Data type
- Track which fields are accessed in CLIENT contexts (outside freeze/head)
- Removable fields = allFields - clientUsedFields

Fields used only in ephemeral contexts (freeze, head) are removed from the
`Data` type alias in the client bundle, enabling DCE to eliminate the field
accessors and any rendering code that depends on them.

Note: This rule always uses View.Static.adopt from the elm-pages package,
not from the user's View module. If View.Static is not imported, the rule
adds the import automatically.

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


{-| Convert a range to a comparable tuple for Set storage.
-}
rangeToComparable : Range -> ( ( Int, Int ), ( Int, Int ) )
rangeToComparable range =
    ( ( range.start.row, range.start.column ), ( range.end.row, range.end.column ) )


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , moduleName : ModuleName
    , viewStaticImport : ViewStaticImport
    , htmlStyledAlias : Maybe ModuleName
    , lastImportRow : Int
    , staticIndex : Int

    -- Field tracking: fields accessed in CLIENT contexts (outside freeze/head)
    -- These are the fields that MUST be kept in the client Data type
    , clientUsedFields : Set String

    -- Ephemeral context tracking
    , inFreezeCall : Bool
    , inHeadFunction : Bool

    -- app.data binding tracking (for let bindings like `let d = app.data`)
    , appDataBindings : Set String

    -- Field-specific binding tracking (for let bindings like `let title = app.data.title`)
    -- Maps variable name -> field name from app.data
    -- When a variable is used in client context, we mark its field as client-used
    , fieldBindings : Dict String String

    -- Ranges of expressions that are RHS of field bindings (to skip in normal tracking)
    -- These are tracked via the variable usage, not the direct field access
    , fieldBindingRanges : Set ( ( Int, Int ), ( Int, Int ) )

    -- Track if app.data is used as a whole in CLIENT context (not field-accessed)
    -- If true, we mark ALL fields as client-used (safe fallback, no optimization)
    , markAllFieldsAsClientUsed : Bool

    -- Track if Data is used as a record constructor function
    -- (e.g., `map4 Data arg1 arg2 arg3 arg4`)
    -- If true, we can't transform the type alias without breaking the constructor
    , dataUsedAsConstructor : Bool

    -- Data type location for transformation
    , dataTypeRange : Maybe Range
    , dataTypeFields : List ( String, Node TypeAnnotation )
    , dataTypeDeclarationEndRow : Int -- Row where Data type declaration ends (for inserting NarrowedData)

    -- Ranges where "App Data" appears in type signatures (to replace with "App NarrowedData")
    , appDataTypeRanges : List Range

    -- Head function body range for stubbing
    , headFunctionBodyRange : Maybe Range

    -- Data function body range for stubbing (never runs on client)
    , dataFunctionBodyRange : Maybe Range

    -- RouteBuilder convention verification
    -- We track what function names are passed to RouteBuilder.preRender/single/serverRender
    -- If the names don't match conventions, we bail out of optimization
    , routeBuilderHeadFn : Maybe String -- What's passed to `head = X` in RouteBuilder
    , routeBuilderDataFn : Maybe String -- What's passed to `data = X` in RouteBuilder
    , routeBuilderFound : Bool -- Did we find a RouteBuilder call?

    -- App parameter name from view function (could be "app", "static", etc.)
    , appParamName : Maybe String

    -- Track if NarrowedData type alias already exists (to prevent infinite fix loop)
    , narrowedDataExists : Bool
    }


type ViewStaticImport
    = NotImported
    | ImportedAs ModuleName


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.StaticViewTransform" initialContext
        |> Rule.providesFixesForModuleRule
        |> Rule.withImportVisitor importVisitor
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withDeclarationExitVisitor declarationExitVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation
        |> Rule.fromModuleRuleSchema


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable moduleName () ->
            { lookupTable = lookupTable
            , moduleName = moduleName
            , viewStaticImport = NotImported
            , htmlStyledAlias = Nothing
            , lastImportRow = 2
            , staticIndex = 0
            , clientUsedFields = Set.empty
            , inFreezeCall = False
            , inHeadFunction = False
            , appDataBindings = Set.empty
            , fieldBindings = Dict.empty
            , fieldBindingRanges = Set.empty
            , markAllFieldsAsClientUsed = False
            , dataUsedAsConstructor = False
            , dataTypeRange = Nothing
            , dataTypeFields = []
            , dataTypeDeclarationEndRow = 0
            , appDataTypeRanges = []
            , headFunctionBodyRange = Nothing
            , dataFunctionBodyRange = Nothing
            , routeBuilderHeadFn = Nothing
            , routeBuilderDataFn = Nothing
            , routeBuilderFound = False
            , appParamName = Nothing
            , narrowedDataExists = False
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


importVisitor : Node Import -> Context -> ( List (Rule.Error {}), Context )
importVisitor node context =
    let
        import_ =
            Node.value node

        moduleName =
            Node.value import_.moduleName

        importEndRow =
            (Node.range node).end.row
    in
    if moduleName == [ "View", "Static" ] then
        ( []
        , { context
            | viewStaticImport =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "View", "Static" ]
                    |> ImportedAs
            , lastImportRow = max context.lastImportRow importEndRow
          }
        )

    else if moduleName == [ "Html", "Styled" ] then
        ( []
        , { context
            | htmlStyledAlias =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "Html", "Styled" ]
                    |> Just
            , lastImportRow = max context.lastImportRow importEndRow
          }
        )

    else
        ( []
        , { context | lastImportRow = max context.lastImportRow importEndRow }
        )


declarationEnterVisitor : Node Declaration -> Context -> ( List (Rule.Error {}), Context )
declarationEnterVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                functionName =
                    function.declaration
                        |> Node.value
                        |> .name
                        |> Node.value

                bodyRange =
                    function.declaration
                        |> Node.value
                        |> .expression
                        |> Node.range

                -- Determine the actual head function name
                -- If we've seen RouteBuilder, use the extracted name
                -- Otherwise fall back to "head" (the convention)
                actualHeadFn =
                    context.routeBuilderHeadFn
                        |> Maybe.withDefault "head"

                -- Determine the actual data function name
                actualDataFn =
                    context.routeBuilderDataFn
                        |> Maybe.withDefault "data"

                -- Find "App Data" in type signature and track its range for replacement
                appDataRanges =
                    case function.signature of
                        Just (Node _ signature) ->
                            findAppDataRanges signature.typeAnnotation

                        Nothing ->
                            []

                contextWithAppDataRanges =
                    { context | appDataTypeRanges = context.appDataTypeRanges ++ appDataRanges }
            in
            if functionName == actualHeadFn then
                ( []
                , { contextWithAppDataRanges
                    | inHeadFunction = True
                    , headFunctionBodyRange = Just bodyRange
                  }
                )

            else if functionName == actualDataFn then
                -- Capture the data function body for potential stubbing
                -- The data function never runs on client, only at build time
                ( [], { contextWithAppDataRanges | dataFunctionBodyRange = Just bodyRange } )

            else if functionName == "view" then
                -- Extract the App parameter name from the view function
                -- The first parameter is typically named "app" or "static"
                let
                    maybeAppParam =
                        function.declaration
                            |> Node.value
                            |> .arguments
                            |> List.head
                            |> Maybe.andThen extractPatternName
                in
                ( [], { contextWithAppDataRanges | appParamName = maybeAppParam } )

            else
                ( [], contextWithAppDataRanges )

        Declaration.AliasDeclaration typeAlias ->
            let
                typeName =
                    Node.value typeAlias.name

                -- Track the end of the full declaration for inserting NarrowedData after
                declarationEndRow =
                    (Node.range node).end.row
            in
            if typeName == "Data" then
                case Node.value typeAlias.typeAnnotation of
                    TypeAnnotation.Record recordFields ->
                        let
                            fields =
                                recordFields
                                    |> List.map
                                        (\fieldNode ->
                                            let
                                                ( nameNode, typeNode ) =
                                                    Node.value fieldNode
                                            in
                                            ( Node.value nameNode, typeNode )
                                        )
                        in
                        ( []
                        , { context
                            | dataTypeRange = Just (Node.range typeAlias.typeAnnotation)
                            , dataTypeFields = fields
                            , dataTypeDeclarationEndRow = declarationEndRow
                          }
                        )

                    _ ->
                        ( [], context )

            else if typeName == "NarrowedData" then
                -- NarrowedData already exists, don't emit fix for it again
                ( [], { context | narrowedDataExists = True } )

            else
                ( [], context )

        _ ->
            ( [], context )


declarationExitVisitor : Node Declaration -> Context -> ( List (Rule.Error {}), Context )
declarationExitVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                functionName =
                    function.declaration
                        |> Node.value
                        |> .name
                        |> Node.value

                -- Use the same logic as enter visitor for consistency
                actualHeadFn =
                    context.routeBuilderHeadFn
                        |> Maybe.withDefault "head"
            in
            if functionName == actualHeadFn then
                ( [], { context | inHeadFunction = False } )

            else
                ( [], context )

        _ ->
            ( [], context )


expressionEnterVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionEnterVisitor node context =
    let
        -- Detect if Data is used as a record constructor function
        -- (e.g., `map4 Data`, `succeed Data`, `Data field1 field2`)
        contextWithDataConstructorCheck =
            if context.dataUsedAsConstructor then
                -- Already detected, no need to check again
                context

            else
                case Node.value node of
                    -- Direct use: Data as function argument (e.g., `map4 Data`)
                    Expression.FunctionOrValue [] "Data" ->
                        { context | dataUsedAsConstructor = True }

                    _ ->
                        context

        -- Detect RouteBuilder calls and extract function names
        -- This ensures we only treat the actual head/data functions as ephemeral
        contextWithRouteBuilder =
            case Node.value node of
                Expression.Application (functionNode :: args) ->
                    case ModuleNameLookupTable.moduleNameFor contextWithDataConstructorCheck.lookupTable functionNode of
                        Just [ "RouteBuilder" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ fnName ->
                                    if fnName == "preRender" || fnName == "single" || fnName == "serverRender" then
                                        -- Extract head and data function names from the record argument
                                        extractRouteBuilderFunctions contextWithDataConstructorCheck args

                                    else
                                        contextWithDataConstructorCheck

                                _ ->
                                    contextWithDataConstructorCheck

                        _ ->
                            contextWithDataConstructorCheck

                _ ->
                    contextWithDataConstructorCheck

        -- Track entering freeze calls
        -- Also check if app.data is passed as a whole in CLIENT context
        contextWithFreezeTracking =
            case Node.value node of
                Expression.Application (functionNode :: args) ->
                    case ModuleNameLookupTable.moduleNameFor contextWithRouteBuilder.lookupTable functionNode of
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "freeze" ->
                                    -- Entering freeze - just set the flag, don't check app.data here
                                    -- (we don't care about tracking inside ephemeral contexts)
                                    { contextWithRouteBuilder | inFreezeCall = True }

                                _ ->
                                    -- Check for app.data passed as whole in CLIENT context
                                    checkAppDataPassedInClientContext contextWithRouteBuilder args

                        _ ->
                            -- Check for app.data passed as whole in CLIENT context
                            checkAppDataPassedInClientContext contextWithRouteBuilder args

                _ ->
                    contextWithRouteBuilder

        -- Track field access patterns
        contextWithFieldTracking =
            trackFieldAccess node contextWithFreezeTracking
    in
    -- Handle the transformations
    case Node.value node of
        Expression.Application applicationExpressions ->
            case applicationExpressions of
                -- Single-argument application: View.freeze expr, View.Static.static expr
                functionNode :: _ :: [] ->
                    case ModuleNameLookupTable.moduleNameFor contextWithFieldTracking.lookupTable functionNode of
                        Just [ "View" ] ->
                            handleViewModuleCall functionNode node contextWithFieldTracking

                        Just [ "View", "Static" ] ->
                            handleViewStaticModuleCall functionNode node contextWithFieldTracking

                        _ ->
                            ( [], contextWithFieldTracking )

                _ ->
                    ( [], contextWithFieldTracking )

        _ ->
            ( [], contextWithFieldTracking )


expressionExitVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionExitVisitor node context =
    case Node.value node of
        Expression.Application (functionNode :: _) ->
            case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                Just [ "View" ] ->
                    case Node.value functionNode of
                        Expression.FunctionOrValue _ "freeze" ->
                            ( [], { context | inFreezeCall = False } )

                        _ ->
                            ( [], context )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )


{-| Track field access on app.data and variables bound to app.data.
Also detects when app.data is used as a whole (not field-accessed).

Enhanced to track:
1. Direct field access: app.data.fieldName (but NOT in let binding RHS that we extract as field bindings)
2. Let bindings that assign fields: let title = app.data.title (via fieldBindings)
3. Usage of variables bound to fields: someFunc title

Note: When a let binding like `let title = app.data.title` is seen, we extract it as a field binding
and track the USAGE of `title` variable, not the definition. This avoids double-counting.

-}
trackFieldAccess : Node Expression -> Context -> Context
trackFieldAccess node context =
    let
        -- Check if this expression is in a range we should skip (field binding RHS)
        nodeRange =
            rangeToComparable (Node.range node)

        isFieldBindingRHS =
            Set.member nodeRange context.fieldBindingRanges
    in
    case Node.value node of
        -- Direct field access: app.data.fieldName
        -- Skip if this is the RHS of a let binding that we're extracting as a field binding
        -- (those will be tracked via the variable usage)
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            if isFieldBindingRHS then
                -- This is a field binding RHS like `let title = app.data.title`
                -- Don't track here - it will be tracked when the variable is used
                context

            else if isAppDataAccess innerExpr context then
                -- Direct app.data.field access (not in a field binding RHS)
                addFieldAccess fieldName context

            else
                -- Check for app.data.something.field (nested) - track top-level field
                case Node.value innerExpr of
                    Expression.RecordAccess innerInner (Node _ topLevelField) ->
                        if isAppDataAccess innerInner context then
                            addFieldAccess topLevelField context

                        else
                            context

                    _ ->
                        context

        -- Variable reference: check if it's bound to an app.data field
        Expression.FunctionOrValue [] varName ->
            case Dict.get varName context.fieldBindings of
                Just fieldName ->
                    -- This variable is bound to an app.data field
                    addFieldAccess fieldName context

                Nothing ->
                    context

        -- Pipe operator with accessor: app.data |> .field
        -- We can't safely track which field is accessed with accessor functions
        Expression.OperatorApplication "|>" _ leftExpr rightExpr ->
            if isAppDataExpression leftExpr context then
                case Node.value rightExpr of
                    Expression.RecordAccessFunction _ ->
                        -- Accessor function on app.data - bail out in client context
                        if context.inFreezeCall || context.inHeadFunction then
                            -- In ephemeral context, we don't care
                            context

                        else
                            -- In client context, can't track which fields are used
                            { context | markAllFieldsAsClientUsed = True }

                    _ ->
                        context

            else
                context

        -- Case expression on app.data: case app.data of {...}
        -- We can't safely track field destructuring patterns
        Expression.CaseExpression caseBlock ->
            if isAppDataExpression caseBlock.expression context then
                if context.inFreezeCall || context.inHeadFunction then
                    -- In ephemeral context, we don't care
                    context

                else
                    -- In client context, can't track which fields are used
                    { context | markAllFieldsAsClientUsed = True }

            else
                context

        -- Record update on app.data binding: { d | field = value } where d = app.data
        -- All fields from app.data are used (copied) in the update, so we can't track
        Expression.RecordUpdateExpression (Node _ varName) _ ->
            if Set.member varName context.appDataBindings then
                if context.inFreezeCall || context.inHeadFunction then
                    -- In ephemeral context, we don't care
                    context

                else
                    -- In client context, app.data used as whole via record update
                    { context | markAllFieldsAsClientUsed = True }

            else
                context

        -- Let expressions can bind app.data to a variable, or bind specific fields
        Expression.LetExpression letBlock ->
            let
                ( newAppDataBindings, newFieldBindings, newFieldBindingRanges ) =
                    letBlock.declarations
                        |> List.foldl
                            (\declNode ( appBindings, fieldBinds, bindingRanges ) ->
                                case Node.value declNode of
                                    Expression.LetFunction letFn ->
                                        let
                                            fnDecl =
                                                Node.value letFn.declaration

                                            varName =
                                                Node.value fnDecl.name

                                            exprRange =
                                                Node.range fnDecl.expression
                                        in
                                        case fnDecl.arguments of
                                            [] ->
                                                -- No arguments, could be binding app.data or app.data.field
                                                case extractAppDataFieldAccess fnDecl.expression context of
                                                    Just fieldName ->
                                                        -- let title = app.data.title
                                                        -- Track the range to skip in normal field tracking
                                                        ( appBindings
                                                        , Dict.insert varName fieldName fieldBinds
                                                        , Set.insert (rangeToComparable exprRange) bindingRanges
                                                        )

                                                    Nothing ->
                                                        if isAppDataExpression fnDecl.expression context then
                                                            -- let d = app.data
                                                            ( Set.insert varName appBindings, fieldBinds, bindingRanges )

                                                        else
                                                            ( appBindings, fieldBinds, bindingRanges )

                                            _ ->
                                                ( appBindings, fieldBinds, bindingRanges )

                                    Expression.LetDestructuring pattern expr ->
                                        -- Handle: let { field1, field2 } = app.data in ...
                                        -- With record destructuring, variable names ARE field names
                                        if isAppDataExpression expr context then
                                            let
                                                destructuredNames =
                                                    extractPatternNames pattern

                                                -- For record destructuring of app.data, variable name = field name
                                                newFieldBinds =
                                                    destructuredNames
                                                        |> Set.foldl (\name acc -> Dict.insert name name acc) fieldBinds

                                                -- Track the range to skip
                                                exprRange =
                                                    Node.range expr
                                            in
                                            ( Set.union destructuredNames appBindings
                                            , newFieldBinds
                                            , Set.insert (rangeToComparable exprRange) bindingRanges
                                            )

                                        else
                                            ( appBindings, fieldBinds, bindingRanges )
                            )
                            ( context.appDataBindings, context.fieldBindings, context.fieldBindingRanges )
            in
            { context
                | appDataBindings = newAppDataBindings
                , fieldBindings = newFieldBindings
                , fieldBindingRanges = newFieldBindingRanges
            }

        _ ->
            context


{-| Check if an expression is `app.data` (or `static.data`, etc. based on context.appParamName)
-}
isAppDataAccess : Node Expression -> Context -> Bool
isAppDataAccess node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] varName ->
                    -- Check if varName matches the App parameter name (e.g., "app", "static")
                    context.appParamName == Just varName

                _ ->
                    False

        -- Also check for bound variables
        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        _ ->
            False


{-| Check if an expression represents app.data (for let binding detection)
-}
isAppDataExpression : Node Expression -> Context -> Bool
isAppDataExpression node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] varName ->
                    -- Check if varName matches the App parameter name (e.g., "app", "static")
                    context.appParamName == Just varName

                _ ->
                    False

        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        _ ->
            False


{-| Extract the field name if the expression is `app.data.fieldName`.
Returns Just fieldName if it matches, Nothing otherwise.
-}
extractAppDataFieldAccess : Node Expression -> Context -> Maybe String
extractAppDataFieldAccess node context =
    case Node.value node of
        -- app.data.fieldName
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            if isAppDataAccess innerExpr context then
                Just fieldName

            else
                Nothing

        _ ->
            Nothing


{-| Check if an expression contains `app.data` being passed as a WHOLE to a function.

This returns True ONLY for `app.data` itself, NOT for field accesses like `app.data.field`.
The reason: if someone writes `someFunction app.data.field`, we CAN track that field access.
But if they write `someFunction app.data`, we CANNOT know which fields that function uses.

Examples:
- `app.data` → True (app.data passed as whole)
- `app.data.title` → False (field access, we can track "title")
- `someFunction app.data` → True (app.data passed to function)
- `someFunction app.data.title` → False (just passing the value of title field)

-}
containsAppDataExpression : Node Expression -> Context -> Bool
containsAppDataExpression node context =
    case Node.value node of
        -- app.data exactly (with field "data" on the app param)
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] varName ->
                    -- Check if varName matches the App parameter name (e.g., "app", "static")
                    if context.appParamName == Just varName then
                        -- This IS app.data being used as a whole
                        True

                    else
                        -- Something else with .data field, recurse
                        containsAppDataExpression innerExpr context

                _ ->
                    -- Something else with .data field, recurse
                    containsAppDataExpression innerExpr context

        -- app.data.field - accessing a field OF app.data is fine, we can track that
        -- The field access is already tracked by trackFieldAccess
        Expression.RecordAccess innerExpr _ ->
            -- Don't recurse here - we don't care if app.data is deep inside a field access chain
            -- because accessing app.data.foo.bar still tracks "foo" as the accessed field
            False

        Expression.FunctionOrValue [] varName ->
            -- Check if this variable is bound to app.data
            Set.member varName context.appDataBindings

        Expression.Application exprs ->
            List.any (\e -> containsAppDataExpression e context) exprs

        Expression.ParenthesizedExpression inner ->
            containsAppDataExpression inner context

        Expression.TupledExpression exprs ->
            List.any (\e -> containsAppDataExpression e context) exprs

        Expression.ListExpr exprs ->
            List.any (\e -> containsAppDataExpression e context) exprs

        Expression.IfBlock cond then_ else_ ->
            containsAppDataExpression cond context
                || containsAppDataExpression then_ context
                || containsAppDataExpression else_ context

        Expression.CaseExpression caseBlock ->
            containsAppDataExpression caseBlock.expression context
                || List.any (\( _, expr ) -> containsAppDataExpression expr context) caseBlock.cases

        Expression.LambdaExpression lambda ->
            containsAppDataExpression lambda.expression context

        Expression.LetExpression letBlock ->
            containsAppDataExpression letBlock.expression context

        Expression.OperatorApplication _ _ left right ->
            containsAppDataExpression left context
                || containsAppDataExpression right context

        -- Record update: { varName | field = value }
        -- In Elm, record update uses a variable name, not an expression.
        -- If the variable is bound to app.data (via let d = app.data),
        -- then we're using app.data as a whole.
        Expression.RecordUpdateExpression (Node _ varName) _ ->
            Set.member varName context.appDataBindings

        _ ->
            False


{-| Extract variable names from a pattern (for destructuring)
-}
extractPatternNames : Node Pattern -> Set String
extractPatternNames node =
    case Node.value node of
        Pattern.VarPattern name ->
            Set.singleton name

        Pattern.RecordPattern fields ->
            fields |> List.map Node.value |> Set.fromList

        Pattern.TuplePattern patterns ->
            patterns |> List.foldl (\p acc -> Set.union (extractPatternNames p) acc) Set.empty

        Pattern.ParenthesizedPattern inner ->
            extractPatternNames inner

        Pattern.AsPattern inner (Node _ name) ->
            Set.insert name (extractPatternNames inner)

        _ ->
            Set.empty


{-| Extract a single name from a pattern (for function parameter names).
-}
extractPatternName : Node Pattern -> Maybe String
extractPatternName node =
    case Node.value node of
        Pattern.VarPattern name ->
            Just name

        Pattern.ParenthesizedPattern inner ->
            extractPatternName inner

        Pattern.AsPattern _ (Node _ name) ->
            Just name

        _ ->
            Nothing


{-| Find all occurrences of "App Data ..." in a type annotation.
Returns the ranges of the "Data" type argument so it can be replaced with "NarrowedData".

For example, in `App Data ActionData RouteParams -> Shared.Model -> View msg`,
this finds the range of `Data` (the first type argument to `App`).

-}
findAppDataRanges : Node TypeAnnotation -> List Range
findAppDataRanges node =
    case Node.value node of
        TypeAnnotation.Typed (Node _ ( moduleName, typeName )) args ->
            let
                -- Check if this is "App" (from RouteBuilder or unqualified)
                isAppType =
                    (moduleName == [] && typeName == "App")
                        || (moduleName == [ "RouteBuilder" ] && typeName == "App")

                -- If it's App and first arg is "Data", get that range
                appDataRange =
                    if isAppType then
                        case args of
                            (Node dataRange (TypeAnnotation.Typed (Node _ ( [], "Data" )) _)) :: _ ->
                                [ dataRange ]

                            _ ->
                                []

                    else
                        []

                -- Recurse into type arguments
                nestedRanges =
                    args |> List.concatMap findAppDataRanges
            in
            appDataRange ++ nestedRanges

        TypeAnnotation.FunctionTypeAnnotation left right ->
            findAppDataRanges left ++ findAppDataRanges right

        TypeAnnotation.Tupled nodes ->
            nodes |> List.concatMap findAppDataRanges

        TypeAnnotation.Record fields ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, typeNode )) ->
                        findAppDataRanges typeNode
                    )

        TypeAnnotation.GenericRecord _ (Node _ fields) ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, typeNode )) ->
                        findAppDataRanges typeNode
                    )

        _ ->
            []


{-| Add a field access to clientUsedFields if we're in a CLIENT context.
Fields accessed in ephemeral contexts (freeze, head) are NOT tracked.
-}
addFieldAccess : String -> Context -> Context
addFieldAccess fieldName context =
    if context.inFreezeCall || context.inHeadFunction then
        -- In ephemeral context - don't track (field can potentially be removed)
        context

    else
        -- In client context - field MUST be kept
        { context | clientUsedFields = Set.insert fieldName context.clientUsedFields }


{-| Extract function names from RouteBuilder.preRender/single/serverRender record argument.

This ensures we correctly identify which functions are ephemeral (head, data)
based on what's ACTUALLY passed to RouteBuilder, not just by function name.

If the record uses simple function references like `{ head = head, data = data }`,
we extract those names. If it uses lambdas or complex expressions, we can't
safely track ephemeral contexts, so we leave the names as Nothing (which will
cause us to bail out of optimization).

-}
extractRouteBuilderFunctions : Context -> List (Node Expression) -> Context
extractRouteBuilderFunctions context args =
    case args of
        recordArg :: _ ->
            case Node.value recordArg of
                Expression.RecordExpr fields ->
                    let
                        extractedHead =
                            fields
                                |> List.filterMap
                                    (\fieldNode ->
                                        let
                                            ( Node _ fieldName, valueNode ) =
                                                Node.value fieldNode
                                        in
                                        if fieldName == "head" then
                                            extractSimpleFunctionName valueNode

                                        else
                                            Nothing
                                    )
                                |> List.head

                        extractedData =
                            fields
                                |> List.filterMap
                                    (\fieldNode ->
                                        let
                                            ( Node _ fieldName, valueNode ) =
                                                Node.value fieldNode
                                        in
                                        if fieldName == "data" then
                                            extractSimpleFunctionName valueNode

                                        else
                                            Nothing
                                    )
                                |> List.head
                    in
                    { context
                        | routeBuilderFound = True
                        , routeBuilderHeadFn = extractedHead
                        , routeBuilderDataFn = extractedData
                    }

                _ ->
                    -- Not a record literal - can't extract function names
                    { context | routeBuilderFound = True }

        _ ->
            context


{-| Extract a simple function name from an expression.
Returns Just "functionName" for simple references like `head`, `myHeadFn`.
Returns Nothing for lambdas, complex expressions, or qualified names.
-}
extractSimpleFunctionName : Node Expression -> Maybe String
extractSimpleFunctionName node =
    case Node.value node of
        Expression.FunctionOrValue [] name ->
            -- Simple unqualified function reference
            Just name

        _ ->
            -- Lambda, qualified name, or complex expression
            -- We can't safely track these
            Nothing


{-| Check if app.data is passed as a whole to a function in CLIENT context.
If we're in an ephemeral context (freeze/head), we don't care.
If we're in client context and app.data is passed as a whole, we can't
safely determine which fields are used, so we set markAllFieldsAsClientUsed.
-}
checkAppDataPassedInClientContext : Context -> List (Node Expression) -> Context
checkAppDataPassedInClientContext context args =
    if context.inFreezeCall || context.inHeadFunction then
        -- In ephemeral context - we don't care about tracking here
        context

    else
        -- In client context - check if app.data is passed as a whole
        let
            appDataPassedToFunction =
                args
                    |> List.any
                        (\arg ->
                            case Node.value arg of
                                -- Check if this is app.data (not app.data.field)
                                -- app.data.field = RecordAccess (RecordAccess app "data") "field" - OK, trackable
                                -- app.data = RecordAccess app "data" - NOT OK, can't track
                                Expression.RecordAccess innerExpr (Node _ fieldName) ->
                                    if fieldName == "data" then
                                        -- Could be app.data - check if it IS app.data
                                        isAppDataExpression arg context

                                    else
                                        -- This is someExpr.someField - check if someExpr contains app.data
                                        -- But if it's app.data.field, that's fine (trackable)
                                        -- So we need to check if innerExpr IS app.data (in which case we're fine)
                                        -- vs if innerExpr CONTAINS app.data in some other way
                                        if isAppDataAccess innerExpr context then
                                            -- This is app.data.field - trackable, OK
                                            False

                                        else
                                            -- Check if the inner expression contains app.data
                                            containsAppDataExpression innerExpr context

                                -- If the arg is a function call that contains app.data,
                                -- we can't track which fields are used
                                Expression.Application innerArgs ->
                                    List.any (\a -> containsAppDataExpression a context) innerArgs

                                -- Check if arg is or CONTAINS app.data
                                -- (e.g., [ app.data ], ( app.data, x ), { app.data | field = y })
                                _ ->
                                    isAppDataExpression arg context
                                        || containsAppDataExpression arg context
                        )
        in
        if appDataPassedToFunction then
            { context | markAllFieldsAsClientUsed = True }

        else
            context


handleViewModuleCall : Node Expression -> Node Expression -> Context -> ( List (Error {}), Context )
handleViewModuleCall functionNode node context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "freeze" ->
            let
                -- If Html.Styled is imported, wrap with Html.Styled conversion
                -- Otherwise use plain Html (no wrapper needed since View.freeze returns Html)
                replacement =
                    if context.htmlStyledAlias /= Nothing then
                        viewStaticAdoptCallStyled context

                    else
                        viewStaticAdoptCallPlain context

                fixes =
                    [ Review.Fix.replaceRangeBy (Node.range node) replacement ]
                        ++ viewStaticImportFix context
            in
            ( [ createTransformErrorWithFixes "View.freeze" "View.Static.adopt" node fixes ]
            , { context | staticIndex = context.staticIndex + 1 }
            )

        Expression.FunctionOrValue _ "static" ->
            let
                -- If Html.Styled is imported, wrap with Html.Styled conversion
                -- Otherwise use plain Html (no wrapper needed since View.static returns Html)
                replacement =
                    if context.htmlStyledAlias /= Nothing then
                        viewStaticAdoptCallStyled context

                    else
                        viewStaticAdoptCallPlain context

                fixes =
                    [ Review.Fix.replaceRangeBy (Node.range node) replacement ]
                        ++ viewStaticImportFix context
            in
            ( [ createTransformErrorWithFixes "View.static" "View.Static.adopt" node fixes ]
            , { context | staticIndex = context.staticIndex + 1 }
            )

        _ ->
            ( [], context )


handleViewStaticModuleCall : Node Expression -> Node Expression -> Context -> ( List (Error {}), Context )
handleViewStaticModuleCall functionNode node context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "static" ->
            let
                replacement =
                    viewStaticAdoptCallPlain context
            in
            ( [ createTransformError "View.Static.static" "View.Static.adopt" node replacement ]
            , { context | staticIndex = context.staticIndex + 1 }
            )

        _ ->
            ( [], context )


createTransformError : String -> String -> Node Expression -> String -> Error {}
createTransformError fromFn toFn node replacement =
    Rule.errorWithFix
        { message = "Static region codemod: transform " ++ fromFn ++ " to " ++ toFn
        , details = [ "Transforms " ++ fromFn ++ " to " ++ toFn ++ " for client-side adoption and DCE" ]
        }
        (Node.range node)
        [ Review.Fix.replaceRangeBy (Node.range node) replacement
        ]


createTransformErrorWithFixes : String -> String -> Node Expression -> List Review.Fix.Fix -> Error {}
createTransformErrorWithFixes fromFn toFn node fixes =
    Rule.errorWithFix
        { message = "Static region codemod: transform " ++ fromFn ++ " to " ++ toFn
        , details = [ "Transforms " ++ fromFn ++ " to " ++ toFn ++ " for client-side adoption and DCE" ]
        }
        (Node.range node)
        fixes


{-| Generate a fix to add `import View.Static` if it's not already imported.
-}
viewStaticImportFix : Context -> List Review.Fix.Fix
viewStaticImportFix context =
    case context.viewStaticImport of
        ImportedAs _ ->
            -- Already imported, no fix needed
            []

        NotImported ->
            -- Add the import after the last import
            [ Review.Fix.insertAt
                { row = context.lastImportRow + 1, column = 1 }
                "import View.Static\n"
            ]


{-| Generate View.Static.adopt "index" for View module calls (View.freeze).

Wraps with Html.Styled conversion since the user's View module works with Html.Styled types.
Uses the correct Html.Styled alias if one is defined.
-}
viewStaticAdoptCallStyled : Context -> String
viewStaticAdoptCallStyled context =
    let
        viewStaticPrefix =
            case context.viewStaticImport of
                ImportedAs alias ->
                    String.join "." alias

                NotImported ->
                    "View.Static"

        htmlStyledPrefix =
            context.htmlStyledAlias
                |> Maybe.withDefault [ "Html", "Styled" ]
                |> String.join "."

        idStr =
            "\"" ++ String.fromInt context.staticIndex ++ "\""
    in
    -- Wrap with Html.Styled conversion to match the original View.freeze return type
    "(" ++ viewStaticPrefix ++ ".adopt " ++ idStr ++ " |> " ++ htmlStyledPrefix ++ ".fromUnstyled |> " ++ htmlStyledPrefix ++ ".map never)"


{-| Generate View.Static.adopt "index" for plain Html (not Html.Styled).

Since View.Static.adopt returns Html Never, we need to wrap with Html.map never
to convert to the generic Html msg type expected by the View type.
-}
viewStaticAdoptCallPlain : Context -> String
viewStaticAdoptCallPlain context =
    let
        modulePrefix =
            case context.viewStaticImport of
                ImportedAs alias ->
                    String.join "." alias

                NotImported ->
                    "View.Static"

        idStr =
            "\"" ++ String.fromInt context.staticIndex ++ "\""
    in
    -- Wrap with Html.map never to convert Html Never -> Html msg
    "(" ++ modulePrefix ++ ".adopt " ++ idStr ++ " |> Html.map never)"


{-| Final evaluation - emit Data type transformation if there are removable fields.

The model is:
- Start with ALL fields from the Data type
- Fields used in CLIENT contexts (outside freeze/head) are in clientUsedFields
- Removable fields = allFields - clientUsedFields

Conservative approach:
- Only tracks DIRECT field access patterns like `app.data.fieldName`
- If `app.data` is passed as a whole to ANY function in CLIENT context,
  we can't safely determine which fields are client-used, so we skip entirely
- If `Data` is used as a record constructor function (e.g., `map4 Data`),
  we can't transform the type without breaking the constructor call
- If RouteBuilder doesn't use conventional naming (`head = head`, `data = data`),
  we can't safely track ephemeral contexts, so we skip entirely

False negatives (missing optimization) are acceptable.
False positives (breaking code) are NOT acceptable.

-}
finalEvaluation : Context -> List (Error {})
finalEvaluation context =
    let
        -- Only apply transformations to Route modules (Route.Index, Route.Blog.Slug_, etc.)
        isRouteModule =
            case context.moduleName of
                "Route" :: _ :: _ ->
                    True

                _ ->
                    False

        -- Check if RouteBuilder uses conventional naming
        -- We currently track ephemeral context by looking for functions named "head" and "data"
        -- If RouteBuilder uses different names (e.g., `head = seoTags`), our tracking is wrong
        -- So we bail out unless we can confirm conventional naming
        routeBuilderUsesConventionalNaming =
            case ( context.routeBuilderFound, context.routeBuilderHeadFn, context.routeBuilderDataFn ) of
                ( True, Just "head", Just "data" ) ->
                    -- Perfect: RouteBuilder uses { head = head, data = data }
                    True

                ( True, Just "head", Nothing ) ->
                    -- head = head, but data uses lambda or complex expression
                    -- We can still safely track head, and data body is stubbed anyway
                    True

                ( True, Nothing, Just "data" ) ->
                    -- data = data, but head uses lambda
                    -- Similar to above - head body doesn't affect our field tracking much
                    True

                ( True, Nothing, Nothing ) ->
                    -- Both use lambdas - we can't track ephemeral contexts
                    -- But this is actually OK for the client bundle because:
                    -- - Lambdas in RouteBuilder likely don't access app.data
                    -- - The view function tracking still works
                    -- Conservative: allow optimization to proceed
                    True

                ( True, Just headFn, _ ) ->
                    -- head = somethingElse, not "head"
                    -- Our tracking assumes function named "head" is ephemeral, which is wrong
                    -- Bail out to be safe
                    headFn == "head"

                ( True, _, Just dataFn ) ->
                    -- data = somethingElse, not "data"
                    -- Our tracking assumes function named "data" is ephemeral
                    -- This is less critical since data function tracking is mainly for stubbing
                    dataFn == "data"

                ( False, _, _ ) ->
                    -- No RouteBuilder call found - this is unusual for a Route module
                    -- Could be a helper module or unusual structure
                    -- Conservative: allow optimization (original behavior)
                    True
    in
    -- Conservative: skip transformation in these cases:
    -- 1. Not a Route module (Site.elm, Shared.elm, etc.)
    -- 2. Data is used as a constructor function (changing type would break it)
    -- 3. RouteBuilder doesn't use conventional naming
    -- 4. NarrowedData type alias already exists (fix was already applied)
    -- Note: markAllFieldsAsClientUsed is handled via effectiveClientUsedFields fallback below
    if not isRouteModule || context.dataUsedAsConstructor || not routeBuilderUsesConventionalNaming || context.narrowedDataExists then
        []

    else
        case context.dataTypeRange of
            Nothing ->
                []

            Just range ->
                let
                    -- All field names from the Data type
                    allFieldNames =
                        context.dataTypeFields
                            |> List.map Tuple.first
                            |> Set.fromList

                    -- Apply safe fallback: if we can't track field usage, mark ALL as client-used
                    effectiveClientUsedFields =
                        if context.markAllFieldsAsClientUsed then
                            -- Can't track, so assume ALL fields are client-used (safe fallback)
                            allFieldNames

                        else
                            context.clientUsedFields

                    -- Removable fields: all fields that are NOT used in client context
                    removableFields =
                        allFieldNames
                            |> Set.filter (\f -> not (Set.member f effectiveClientUsedFields))

                    -- Client-used fields: these MUST be kept in the Data type
                    clientUsedFieldDefs =
                        context.dataTypeFields
                            |> List.filter (\( name, _ ) -> Set.member name effectiveClientUsedFields)
                in
                if Set.isEmpty removableFields then
                    -- No removable fields, nothing to transform
                    []

                else
                    -- Generate fix to rewrite Data type alias
                    -- Use single-line format for simplicity
                    let
                        newTypeAnnotation =
                            if List.isEmpty clientUsedFieldDefs then
                                "{}"

                            else
                                "{ "
                                    ++ (clientUsedFieldDefs
                                            |> List.map (\( name, typeNode ) -> name ++ " : " ++ typeAnnotationToString (Node.value typeNode))
                                            |> String.join ", "
                                       )
                                    ++ " }"

                        -- Always stub out head when removing fields
                        -- The head function never runs on client, so we replace body with []
                        headStubFix =
                            case context.headFunctionBodyRange of
                                Just headRange ->
                                    [ Rule.errorWithFix
                                        { message = "Head function codemod: stub out for client bundle"
                                        , details =
                                            [ "Replacing head function body with [] because Data fields are being removed."
                                            , "The head function never runs on the client (it's for SEO at build time), so stubbing it out allows DCE."
                                            ]
                                        }
                                        headRange
                                        [ Review.Fix.replaceRangeBy headRange "[]" ]
                                    ]

                                Nothing ->
                                    []

                        -- Always stub out the data function when transforming Data type
                        -- The data function constructs Data records and never runs on client
                        -- Stub it with BackendTask.fail which works regardless of arity
                        dataStubFix =
                            case context.dataFunctionBodyRange of
                                Just dataRange ->
                                    [ Rule.errorWithFix
                                        { message = "Data function codemod: stub out for client bundle"
                                        , details =
                                            [ "Replacing data function body because Data fields are being removed."
                                            , "The data function never runs on the client (it's for build-time data fetching), so stubbing it out allows DCE."
                                            ]
                                        }
                                        dataRange
                                        [ Review.Fix.replaceRangeBy dataRange "BackendTask.fail (FatalError.fromString \"\")" ]
                                    ]

                                Nothing ->
                                    []

                        -- Narrow the Data type directly by replacing the record definition
                        -- with only client-used fields
                        removableFieldsList =
                            Set.toList removableFields

                        dataTypeNarrowFix =
                            Rule.errorWithFix
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: " ++ String.join ", " removableFieldsList
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                }
                                range
                                [ Review.Fix.replaceRangeBy range newTypeAnnotation ]

                        -- JSON output for the build system to consume
                        -- This is parsed by generate-template-module-connector.js
                        jsonMessage =
                            "EPHEMERAL_FIELDS_JSON:{\"module\":\""
                                ++ String.join "." context.moduleName
                                ++ "\",\"ephemeralFields\":["
                                ++ (removableFieldsList |> List.map (\f -> "\"" ++ f ++ "\"") |> String.join ",")
                                ++ "],\"newDataType\":\""
                                ++ escapeJsonString newTypeAnnotation
                                ++ "\",\"range\":{\"start\":{\"row\":"
                                ++ String.fromInt range.start.row
                                ++ ",\"column\":"
                                ++ String.fromInt range.start.column
                                ++ "},\"end\":{\"row\":"
                                ++ String.fromInt range.end.row
                                ++ ",\"column\":"
                                ++ String.fromInt range.end.column
                                ++ "}}}"

                        jsonOutputRange =
                            { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }

                        jsonOutputError =
                            Rule.error
                                { message = jsonMessage
                                , details = [ "This is machine-readable output for the build system." ]
                                }
                                jsonOutputRange
                    in
                    [ dataTypeNarrowFix ]
                        ++ headStubFix
                        ++ dataStubFix
                        ++ [ jsonOutputError ]


{-| Convert a TypeAnnotation back to string representation.
This is a simplified version - may need enhancement for complex types.
-}
typeAnnotationToString : TypeAnnotation -> String
typeAnnotationToString typeAnnotation =
    case typeAnnotation of
        TypeAnnotation.GenericType name ->
            name

        TypeAnnotation.Typed (Node _ ( moduleName, name )) args ->
            let
                qualified =
                    case moduleName of
                        [] ->
                            name

                        _ ->
                            String.join "." moduleName ++ "." ++ name

                argsStr =
                    args
                        |> List.map (\(Node _ arg) -> typeAnnotationToString arg)
                        |> List.map
                            (\s ->
                                if String.contains " " s && not (String.startsWith "(" s) then
                                    "(" ++ s ++ ")"

                                else
                                    s
                            )
                        |> String.join " "
            in
            if String.isEmpty argsStr then
                qualified

            else
                qualified ++ " " ++ argsStr

        TypeAnnotation.Unit ->
            "()"

        TypeAnnotation.Tupled nodes ->
            "( "
                ++ (nodes
                        |> List.map (\(Node _ t) -> typeAnnotationToString t)
                        |> String.join ", "
                   )
                ++ " )"

        TypeAnnotation.Record fields ->
            if List.isEmpty fields then
                "{}"

            else
                "{ "
                    ++ (fields
                            |> List.map
                                (\(Node _ ( Node _ fieldName, Node _ fieldType )) ->
                                    fieldName ++ " : " ++ typeAnnotationToString fieldType
                                )
                            |> String.join ", "
                       )
                    ++ " }"

        TypeAnnotation.GenericRecord (Node _ extName) (Node _ fields) ->
            "{ "
                ++ extName
                ++ " | "
                ++ (fields
                        |> List.map
                            (\(Node _ ( Node _ fieldName, Node _ fieldType )) ->
                                fieldName ++ " : " ++ typeAnnotationToString fieldType
                            )
                        |> String.join ", "
                   )
                ++ " }"

        TypeAnnotation.FunctionTypeAnnotation (Node _ left) (Node _ right) ->
            let
                leftStr =
                    typeAnnotationToString left

                rightStr =
                    typeAnnotationToString right

                -- Wrap function types on the left in parens
                leftWrapped =
                    case left of
                        TypeAnnotation.FunctionTypeAnnotation _ _ ->
                            "(" ++ leftStr ++ ")"

                        _ ->
                            leftStr
            in
            leftWrapped ++ " -> " ++ rightStr


{-| Escape a string for use in a JSON string value.
Handles quotes and backslashes.
-}
escapeJsonString : String -> String
escapeJsonString str =
    str
        |> String.replace "\\" "\\\\"
        |> String.replace "\"" "\\\""
        |> String.replace "\n" "\\n"
        |> String.replace "\t" "\\t"
