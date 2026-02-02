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
import Pages.Review.PersistentFieldTracking as PersistentFieldTracking
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


{-| Convert a range to a comparable tuple for Set storage.
-}
rangeToComparable : Range -> ( ( Int, Int ), ( Int, Int ) )
rangeToComparable range =
    ( ( range.start.row, range.start.column ), ( range.end.row, range.end.column ) )


{-| Analysis of a helper function's field usage on its first parameter.
-}
type alias HelperAnalysis =
    PersistentFieldTracking.HelperAnalysis


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
    , currentFunctionName : Maybe String

    -- Per-function field tracking (for non-conventional head function names)
    -- Maps function name -> fields accessed outside freeze in that function
    -- Used in finalEvaluation to exclude fields accessed by the actual head function
    , perFunctionClientFields : Dict String (Set String)

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

    -- Helper function analysis: maps function name -> analysis of what fields it accesses
    -- Used to determine which fields a helper uses when app.data is passed to it
    , helperFunctions : Dict String HelperAnalysis

    -- Pending helper calls: function names called with app.data in client context
    -- These need to be resolved in finalEvaluation after all helpers are analyzed
    -- Nothing = unknown function (mark all fields), Just name = lookup in helperFunctions
    , pendingHelperCalls : List (Maybe String)

    -- Helpers called with app.data inside freeze context
    -- These can have their type annotations updated from Data to Ephemeral
    , helpersCalledInFreeze : Set String

    -- Ranges where "Data" appears in helper type annotations (maps function name -> list of ranges)
    -- Used to replace Data with Ephemeral for freeze-only helpers
    , helperDataTypeRanges : Dict String (List Range)
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
            , currentFunctionName = Nothing
            , perFunctionClientFields = Dict.empty
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
            , helperFunctions = Dict.empty
            , pendingHelperCalls = []
            , helpersCalledInFreeze = Set.empty
            , helperDataTypeRanges = Dict.empty
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
                    { context
                        | appDataTypeRanges = context.appDataTypeRanges ++ appDataRanges
                        , currentFunctionName = Just functionName
                    }
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
                            |> Maybe.andThen PersistentFieldTracking.extractPatternName
                in
                ( [], { contextWithAppDataRanges | appParamName = maybeAppParam } )

            else
                -- Analyze non-special functions as potential helpers
                -- This allows us to track which fields they access when called with app.data
                let
                    helperAnalysis =
                        PersistentFieldTracking.analyzeHelperFunction function

                    -- Find all ranges where "Data" appears in the type annotation
                    -- These can be replaced with "Ephemeral" for freeze-only helpers
                    dataRangesInSignature =
                        case function.signature of
                            Just (Node _ signature) ->
                                findDataTypeRanges signature.typeAnnotation

                            Nothing ->
                                []

                    contextWithDataRanges =
                        if List.isEmpty dataRangesInSignature then
                            contextWithAppDataRanges

                        else
                            { contextWithAppDataRanges
                                | helperDataTypeRanges =
                                    Dict.insert functionName dataRangesInSignature contextWithAppDataRanges.helperDataTypeRanges
                            }

                    contextWithHelper =
                        case helperAnalysis of
                            Just analysis ->
                                { contextWithDataRanges
                                    | helperFunctions =
                                        Dict.insert functionName analysis contextWithDataRanges.helperFunctions
                                }

                            Nothing ->
                                contextWithDataRanges
                in
                ( [], contextWithHelper )

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
                ( [], { context | inHeadFunction = False, currentFunctionName = Nothing } )

            else
                ( [], { context | currentFunctionName = Nothing } )

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
        -- Also check if app.data is passed as a whole in CLIENT or FREEZE context
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
                                    -- Check for app.data passed as whole in CLIENT or FREEZE context
                                    checkAppDataPassedToHelper contextWithRouteBuilder functionNode args

                        _ ->
                            -- Check for app.data passed as whole in CLIENT or FREEZE context
                            checkAppDataPassedToHelper contextWithRouteBuilder functionNode args

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

        -- Pipe operators with accessor: app.data |> .field or .field <| app.data
        Expression.OperatorApplication op _ leftExpr rightExpr ->
            case extractAppDataPipeAccessorField op leftExpr rightExpr context of
                Just fieldName ->
                    addFieldAccess fieldName context

                Nothing ->
                    context

        -- Accessor function application: .field app.data
        -- This is semantically equivalent to app.data |> .field
        -- We can track the specific field being accessed
        Expression.Application [ functionNode, argNode ] ->
            case Node.value functionNode of
                Expression.RecordAccessFunction accessorName ->
                    if isAppDataAccess argNode context then
                        -- Extract field name (RecordAccessFunction stores ".fieldName")
                        let
                            fieldName =
                                String.dropLeft 1 accessorName
                        in
                        -- Track this specific field access
                        addFieldAccess fieldName context

                    else
                        context

                _ ->
                    context

        -- Case expression on app.data: case app.data of {...}
        -- Track record patterns, bail out on variable patterns
        Expression.CaseExpression caseBlock ->
            if isAppDataAccess caseBlock.expression context then
                if context.inFreezeCall || context.inHeadFunction then
                    -- In ephemeral context, we don't care
                    context

                else
                    -- In client context, try to extract record pattern fields
                    let
                        maybeFieldSets =
                            caseBlock.cases
                                |> List.map (\( pattern, _ ) -> PersistentFieldTracking.extractRecordPatternFields pattern)

                        allTrackable =
                            List.all (\m -> m /= Nothing) maybeFieldSets
                    in
                    if allTrackable then
                        -- All patterns are record patterns - track the fields
                        let
                            allFields =
                                maybeFieldSets
                                    |> List.filterMap identity
                                    |> List.foldl Set.union Set.empty
                        in
                        Set.foldl addFieldAccess context allFields

                    else
                        -- Some patterns are untrackable (variable, etc.) - bail out
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
                                                        if isAppDataAccess fnDecl.expression context then
                                                            -- let d = app.data
                                                            ( Set.insert varName appBindings, fieldBinds, bindingRanges )

                                                        else
                                                            ( appBindings, fieldBinds, bindingRanges )

                                            _ ->
                                                ( appBindings, fieldBinds, bindingRanges )

                                    Expression.LetDestructuring pattern expr ->
                                        -- Handle: let { field1, field2 } = app.data in ...
                                        -- With record destructuring, variable names ARE field names
                                        if isAppDataAccess expr context then
                                            let
                                                destructuredNames =
                                                    PersistentFieldTracking.extractPatternNames pattern

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


{-| Check if a function node is a call to View.freeze.
-}
isViewFreezeCall : Node Expression -> Context -> Bool
isViewFreezeCall functionNode context =
    PersistentFieldTracking.isViewFreezeCall functionNode context.lookupTable


{-| Check if an expression is `app.data` (or `static.data`, etc. based on context.appParamName)
-}
isAppDataAccess : Node Expression -> Context -> Bool
isAppDataAccess node context =
    PersistentFieldTracking.isAppDataAccess node context.appParamName context.appDataBindings




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
Delegates to shared implementation in PersistentFieldTracking.
-}
containsAppDataExpression : Node Expression -> Context -> Bool
containsAppDataExpression node context =
    PersistentFieldTracking.containsAppDataExpression
        node
        context.appParamName
        context.appDataBindings
        (\fn -> isViewFreezeCall fn context)


{-| Extract field name from pipe operator with accessor pattern on app.data.
-}
extractAppDataPipeAccessorField : String -> Node Expression -> Node Expression -> Context -> Maybe String
extractAppDataPipeAccessorField op leftExpr rightExpr context =
    PersistentFieldTracking.extractAppDataPipeAccessorField op leftExpr rightExpr context.appParamName context.appDataBindings


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


{-| Find all ranges where "Data" appears as a type in a type annotation.

This is used to replace Data with Ephemeral in freeze-only helper annotations.
Returns the ranges of the "Data" type references (not the full Typed node).

-}
findDataTypeRanges : Node TypeAnnotation -> List Range
findDataTypeRanges node =
    case Node.value node of
        TypeAnnotation.Typed (Node range ( [], "Data" )) args ->
            -- Found "Data" type! Return its range, plus check any type args
            range :: List.concatMap findDataTypeRanges args

        TypeAnnotation.Typed _ args ->
            -- Not Data, but check type arguments
            List.concatMap findDataTypeRanges args

        TypeAnnotation.FunctionTypeAnnotation left right ->
            findDataTypeRanges left ++ findDataTypeRanges right

        TypeAnnotation.Tupled nodes ->
            List.concatMap findDataTypeRanges nodes

        TypeAnnotation.Record fields ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, typeNode )) ->
                        findDataTypeRanges typeNode
                    )

        TypeAnnotation.GenericRecord _ (Node _ fields) ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, typeNode )) ->
                        findDataTypeRanges typeNode
                    )

        _ ->
            []


{-| Add a field access to clientUsedFields if we're in a CLIENT context.
Fields accessed in ephemeral contexts (freeze, head) are NOT tracked.

Also tracks per-function field accesses for non-conventional head function names.
If the head function is defined before RouteBuilder, we initially track its field
accesses as client-used. In finalEvaluation, we subtract these fields when we
discover the actual head function name.
-}
addFieldAccess : String -> Context -> Context
addFieldAccess fieldName context =
    if context.inFreezeCall || context.inHeadFunction then
        -- In ephemeral context - don't track (field can potentially be removed)
        context

    else
        -- In client context - field MUST be kept
        -- Also track per-function for non-conventional head function handling
        let
            updatedPerFunction =
                case context.currentFunctionName of
                    Just fnName ->
                        Dict.update fnName
                            (\maybeFields ->
                                case maybeFields of
                                    Just fields ->
                                        Just (Set.insert fieldName fields)

                                    Nothing ->
                                        Just (Set.singleton fieldName)
                            )
                            context.perFunctionClientFields

                    Nothing ->
                        context.perFunctionClientFields
        in
        { context
            | clientUsedFields = Set.insert fieldName context.clientUsedFields
            , perFunctionClientFields = updatedPerFunction
        }


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


{-| Check if app.data is passed as a whole to a function.

In CLIENT context: track as pending helper call for field usage analysis.
In FREEZE context: track as helper called in freeze for potential stubbing.

Instead of immediately resolving helper lookups (which may fail if the helper
is declared after the call site), we store pending helper calls to be resolved
in finalEvaluation after all helper functions have been analyzed.

  - Just funcName = local function with app.data passed DIRECTLY, will look up in helperFunctions later
  - Nothing = can't track (qualified function, app.data wrapped in list/tuple/etc.)

-}
checkAppDataPassedToHelper : Context -> Node Expression -> List (Node Expression) -> Context
checkAppDataPassedToHelper context functionNode args =
    let
        classification =
            PersistentFieldTracking.classifyAppDataArguments
                functionNode
                args
                context.appParamName
                context.appDataBindings
                (\fn -> isViewFreezeCall fn context)
                (\expr -> containsAppDataExpression expr context)
    in
    -- Skip if this is an accessor function application like .field app.data
    -- which is already handled by trackFieldAccess
    if classification.isAccessorApplication then
        context

    else if context.inFreezeCall || context.inHeadFunction then
        -- In ephemeral context (freeze/head)
        -- Track local functions called with app.data for potential stubbing
        case classification.maybeFuncName of
            Just funcName ->
                if classification.hasDirectAppData || classification.hasWrappedAppData then
                    -- Local function called with app.data in freeze context
                    { context | helpersCalledInFreeze = Set.insert funcName context.helpersCalledInFreeze }

                else
                    context

            Nothing ->
                -- Qualified or complex function - we can't stub it, but that's OK
                -- in freeze context since the code won't run on client anyway
                context

    else
        -- In client context - check if app.data is passed as a whole
        if classification.hasWrappedAppData then
            -- app.data is wrapped in list/tuple/etc. - can't track, bail out
            { context | pendingHelperCalls = Nothing :: context.pendingHelperCalls }

        else if classification.hasDirectAppData then
            -- app.data passed directly - may be able to track via helper analysis
            case classification.maybeFuncName of
                Just funcName ->
                    -- Local function - store name for lookup in finalEvaluation
                    { context | pendingHelperCalls = Just funcName :: context.pendingHelperCalls }

                Nothing ->
                    -- Qualified or complex function expression - can't look up
                    { context | pendingHelperCalls = Nothing :: context.pendingHelperCalls }

        else
            context


handleViewModuleCall : Node Expression -> Node Expression -> Context -> ( List (Error {}), Context )
handleViewModuleCall functionNode node context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ fnName ->
            if fnName == "freeze" || fnName == "static" then
                let
                    -- If Html.Styled is imported, wrap with Html.Styled conversion
                    -- Otherwise use plain Html
                    replacement =
                        if context.htmlStyledAlias /= Nothing then
                            viewStaticAdoptCallStyled context

                        else
                            viewStaticAdoptCallPlain context

                    fixes =
                        [ Review.Fix.replaceRangeBy (Node.range node) replacement ]
                            ++ viewStaticImportFix context

                    fromFn =
                        "View." ++ fnName
                in
                ( [ createTransformErrorWithFixes fromFn "View.Static.adopt" node fixes ]
                , { context | staticIndex = context.staticIndex + 1 }
                )

            else
                ( [], context )

        _ ->
            ( [], context )


handleViewStaticModuleCall : Node Expression -> Node Expression -> Context -> ( List (Error {}), Context )
handleViewStaticModuleCall functionNode node context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "static" ->
            let
                replacement =
                    viewStaticAdoptCallPlain context

                fixes =
                    [ Review.Fix.replaceRangeBy (Node.range node) replacement ]
            in
            ( [ createTransformErrorWithFixes "View.Static.static" "View.Static.adopt" node fixes ]
            , { context | staticIndex = context.staticIndex + 1 }
            )

        _ ->
            ( [], context )


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

        -- Determine the actual head function name from RouteBuilder
        -- This handles non-conventional naming like { head = seoTags }
        actualHeadFn =
            context.routeBuilderHeadFn |> Maybe.withDefault "head"

        -- Fields to subtract from clientUsedFields because they were accessed in the head function
        -- This handles the case where the head function is defined BEFORE RouteBuilder is seen,
        -- so we initially tracked its field accesses as client-used. Now we correct that.
        headFunctionFields =
            if actualHeadFn /= "head" then
                -- Non-conventional head function name - look up fields accessed in that function
                Dict.get actualHeadFn context.perFunctionClientFields
                    |> Maybe.withDefault Set.empty

            else
                -- Conventional naming - inHeadFunction was set correctly during traversal
                Set.empty
    in
    -- Conservative: skip transformation in these cases:
    -- 1. Not a Route module (Site.elm, Shared.elm, etc.)
    -- 2. Data is used as a constructor function (changing type would break it)
    -- 3. NarrowedData type alias already exists (fix was already applied)
    -- Note: markAllFieldsAsClientUsed is handled via effectiveClientUsedFields fallback below
    if not isRouteModule then
        -- Not a Route module, no transformation needed (this is expected for Site.elm, Shared.elm, etc.)
        []

    else if context.narrowedDataExists then
        -- Already transformed, skip
        []

    else if context.dataUsedAsConstructor then
        -- Emit diagnostic: Data used as constructor prevents optimization
        [ emitDiagnostic context.moduleName
            "data_used_as_constructor"
            "Data type is used as a record constructor function (e.g., `map4 Data`). Cannot narrow the type without breaking the constructor call."
        ]

    else
        case context.dataTypeRange of
            Nothing ->
                -- No Data type found - nothing to optimize
                []

            Just range ->
                let
                    -- All field names from the Data type
                    allFieldNames =
                        context.dataTypeFields
                            |> List.map Tuple.first
                            |> Set.fromList

                    -- Resolve pending helper calls against the now-complete helperFunctions dict
                    -- Returns (additionalClientUsedFields, shouldMarkAllFieldsAsClientUsed)
                    ( resolvedHelperFields, unresolvedHelperCalls ) =
                        PersistentFieldTracking.resolvePendingHelperCalls
                            context.pendingHelperCalls
                            context.helperFunctions

                    -- Combine direct field accesses with helper-resolved fields
                    combinedClientUsedFields =
                        Set.union context.clientUsedFields resolvedHelperFields

                    -- Subtract fields accessed by the head function (for non-conventional naming)
                    -- When head = seoTags and seoTags is defined before RouteBuilder,
                    -- its field accesses were initially tracked as client-used. Now we correct that.
                    correctedClientUsedFields =
                        Set.diff combinedClientUsedFields headFunctionFields

                    -- Apply safe fallback: if we can't track field usage, mark ALL as client-used
                    effectiveClientUsedFields =
                        if context.markAllFieldsAsClientUsed || unresolvedHelperCalls then
                            -- Can't track, so assume ALL fields are client-used (safe fallback)
                            allFieldNames

                        else
                            correctedClientUsedFields

                    -- Removable fields: all fields that are NOT used in client context
                    removableFields =
                        allFieldNames
                            |> Set.filter (\f -> not (Set.member f effectiveClientUsedFields))

                    -- Client-used fields: these MUST be kept in the Data type
                    clientUsedFieldDefs =
                        context.dataTypeFields
                            |> List.filter (\( name, _ ) -> Set.member name effectiveClientUsedFields)
                    -- Track WHY all fields might be client-used (for diagnostics)
                    skipReason =
                        if context.markAllFieldsAsClientUsed then
                            Just "app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)"

                        else if unresolvedHelperCalls then
                            Just "app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)"

                        else
                            Nothing
                in
                if Set.isEmpty removableFields then
                    -- No removable fields - emit diagnostic if there was a specific reason
                    case skipReason of
                        Just reason ->
                            [ emitDiagnostic context.moduleName
                                "all_fields_client_used"
                                ("No fields could be removed from Data type. " ++ reason)
                            ]

                        Nothing ->
                            -- All fields are legitimately used in client context - no diagnostic needed
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
                                            |> List.map (\( name, typeNode ) -> name ++ " : " ++ PersistentFieldTracking.typeAnnotationToString (Node.value typeNode))
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

                        -- Find helpers that are ONLY called from freeze context (not from client)
                        -- These need their type annotations updated from Data to Ephemeral
                        helpersCalledInClientContext =
                            context.pendingHelperCalls
                                |> List.filterMap identity
                                |> Set.fromList

                        freezeOnlyHelpers =
                            context.helpersCalledInFreeze
                                |> Set.filter (\name -> not (Set.member name helpersCalledInClientContext))

                        -- Find freeze-only helpers that have Data in their type annotation
                        -- These need Data replaced with Ephemeral to continue type-checking
                        helpersNeedingEphemeral =
                            freezeOnlyHelpers
                                |> Set.filter (\name -> Dict.member name context.helperDataTypeRanges)

                        -- Narrow the Data type directly by replacing the record definition
                        -- with only client-used fields
                        removableFieldsList =
                            Set.toList removableFields

                        -- Collect all helper annotation Data->Ephemeral replacements
                        helperAnnotationReplacements =
                            helpersNeedingEphemeral
                                |> Set.toList
                                |> List.concatMap
                                    (\helperName ->
                                        case Dict.get helperName context.helperDataTypeRanges of
                                            Just dataRanges ->
                                                dataRanges
                                                    |> List.map
                                                        (\dataRange ->
                                                            Review.Fix.replaceRangeBy dataRange "Ephemeral"
                                                        )

                                            Nothing ->
                                                []
                                    )

                        -- Generate Ephemeral type insertion if needed
                        ephemeralTypeInsertion =
                            if Set.isEmpty helpersNeedingEphemeral then
                                []

                            else
                                let
                                    fullTypeAnnotation =
                                        "{ "
                                            ++ (context.dataTypeFields
                                                    |> List.map (\( name, typeNode ) -> name ++ " : " ++ PersistentFieldTracking.typeAnnotationToString (Node.value typeNode))
                                                    |> String.join ", "
                                               )
                                            ++ " }"

                                    insertPosition =
                                        { row = context.dataTypeDeclarationEndRow + 1, column = 1 }
                                in
                                [ Review.Fix.insertAt insertPosition
                                    ("\n\ntype alias Ephemeral =\n    " ++ fullTypeAnnotation ++ "\n")
                                ]

                        -- Combine all fixes into a single error (Data narrowing + Ephemeral generation + annotation updates)
                        allDataTypeFixes =
                            [ Review.Fix.replaceRangeBy range newTypeAnnotation ]
                                ++ ephemeralTypeInsertion
                                ++ helperAnnotationReplacements

                        dataTypeNarrowFix =
                            Rule.errorWithFix
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: " ++ String.join ", " removableFieldsList
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                        ++ (if Set.isEmpty helpersNeedingEphemeral then
                                                []

                                            else
                                                [ "Generating Ephemeral type alias and updating helper annotations for: "
                                                    ++ String.join ", " (Set.toList helpersNeedingEphemeral)
                                                ]
                                           )
                                }
                                range
                                allDataTypeFixes

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


{-| Emit a diagnostic message about why optimization was skipped or limited.
These are informational messages to help users understand the optimization behavior.
The format is JSON for easy parsing by the build system.
-}
emitDiagnostic : ModuleName -> String -> String -> Error {}
emitDiagnostic moduleName reason details =
    let
        moduleNameStr =
            String.join "." moduleName

        jsonMessage =
            "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\""
                ++ moduleNameStr
                ++ "\",\"reason\":\""
                ++ reason
                ++ "\",\"details\":\""
                ++ escapeJsonString details
                ++ "\"}"
    in
    Rule.error
        { message = jsonMessage
        , details = [ details ]
        }
        -- Use a dummy range at start of file
        { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
