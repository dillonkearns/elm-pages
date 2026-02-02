module Pages.Review.ServerDataTransform exposing (rule)

{-| This rule transforms Route modules for the server/CLI bundle.

It performs the following transformations:

1. Renames `type alias Data = {...}` to `type alias Ephemeral = {...}`
2. Creates new `type alias Data = {...}` with only persistent fields
3. Generates `ephemeralToData : Ephemeral -> Data` conversion function

This enables the server to:
- Render views using the full `Ephemeral` type (all fields available)
- Encode only `Data` for wire transmission (reduced payload)
- Use standard Wire3 encoders/decoders for `Data` on both server and client

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Module as Module exposing (Module)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


{-| Analysis of a helper function's field usage on its first parameter.
-}
type alias HelperAnalysis =
    { paramName : String -- First parameter name
    , accessedFields : Set String -- Fields accessed on first param (e.g., param.field)
    , isTrackable : Bool -- False if param is used in ways we can't track
    }


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , moduleName : ModuleName

    -- Field tracking (same as client-side)
    , fieldsInFreeze : Set String
    , fieldsInHead : Set String
    , fieldsOutsideFreeze : Set String
    , inFreezeCall : Bool
    , inHeadFunction : Bool

    -- app.data binding tracking
    , appDataBindings : Set String

    -- App parameter name from view function (could be "app", "static", etc.)
    , appParamName : Maybe String

    -- Track where Data is used as a record constructor (needs to become Ephemeral)
    , dataConstructorRanges : List Range

    -- Data type location and fields
    , dataTypeRange : Maybe Range
    , dataTypeFields : List ( String, Node TypeAnnotation )

    -- End of Data type declaration for inserting new types
    , dataTypeEndRow : Int

    -- Track data function signature for updating Data -> Ephemeral
    , dataFunctionSignatureRange : Maybe Range
    , dataFunctionSignature : Maybe String

    -- Track if Ephemeral type already exists (transformation already applied)
    , hasEphemeralType : Bool

    -- Track all type references to Data (need to become Ephemeral)
    , dataTypeReferenceRanges : List Range

    -- Track range after "Data" in exposing list for inserting ", Ephemeral"
    , dataExportRange : Maybe Range

    -- Helper function analysis: maps function name -> analysis of what fields it accesses
    -- Used to determine which fields a helper uses when app.data is passed to it
    , helperFunctions : Dict String HelperAnalysis

    -- Pending helper calls: function names called with app.data in client context
    -- These need to be resolved in finalEvaluation after all helpers are analyzed
    -- Nothing = unknown function (mark all fields), Just name = lookup in helperFunctions
    , pendingHelperCalls : List (Maybe String)
    }


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.ServerDataTransform" initialContext
        |> Rule.providesFixesForModuleRule
        |> Rule.withModuleDefinitionVisitor moduleDefinitionVisitor
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withDeclarationExitVisitor declarationExitVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation
        |> Rule.fromModuleRuleSchema


{-| Visit module definition to find where "Data" is exported.
-}
moduleDefinitionVisitor : Node Module -> Context -> ( List (Error {}), Context )
moduleDefinitionVisitor node context =
    case Node.value node of
        Module.NormalModule { exposingList } ->
            case Node.value exposingList of
                Exposing.Explicit exposedItems ->
                    -- Find the "Data" export and check if "Ephemeral" is already exported
                    let
                        dataExportRange =
                            exposedItems
                                |> List.filterMap
                                    (\exposedItem ->
                                        case Node.value exposedItem of
                                            Exposing.TypeOrAliasExpose "Data" ->
                                                Just (Node.range exposedItem)

                                            _ ->
                                                Nothing
                                    )
                                |> List.head

                        ephemeralAlreadyExported =
                            exposedItems
                                |> List.any
                                    (\exposedItem ->
                                        case Node.value exposedItem of
                                            Exposing.TypeOrAliasExpose "Ephemeral" ->
                                                True

                                            _ ->
                                                False
                                    )
                    in
                    -- Only set dataExportRange if Ephemeral is NOT already exported
                    -- Note: Don't set hasEphemeralType here - that's only for detecting
                    -- if the actual `type alias Ephemeral` declaration exists
                    if ephemeralAlreadyExported then
                        ( [], context )

                    else
                        ( [], { context | dataExportRange = dataExportRange } )

                Exposing.All _ ->
                    -- Exposing everything, Ephemeral will be exposed automatically
                    ( [], context )

        _ ->
            ( [], context )


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable moduleName () ->
            { lookupTable = lookupTable
            , moduleName = moduleName
            , fieldsInFreeze = Set.empty
            , fieldsInHead = Set.empty
            , fieldsOutsideFreeze = Set.empty
            , inFreezeCall = False
            , inHeadFunction = False
            , appDataBindings = Set.empty
            , appParamName = Nothing
            , dataConstructorRanges = []
            , dataTypeRange = Nothing
            , dataTypeFields = []
            , dataTypeEndRow = 0
            , dataFunctionSignatureRange = Nothing
            , dataFunctionSignature = Nothing
            , hasEphemeralType = False
            , dataTypeReferenceRanges = []
            , dataExportRange = Nothing
            , helperFunctions = Dict.empty
            , pendingHelperCalls = []
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


declarationEnterVisitor : Node Declaration -> Context -> ( List (Error {}), Context )
declarationEnterVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                functionName =
                    function.declaration
                        |> Node.value
                        |> .name
                        |> Node.value

                -- Collect Data type references from the function signature
                dataRefs =
                    case function.signature of
                        Just signatureNode ->
                            extractDataTypeReferences (Node.value signatureNode).typeAnnotation

                        Nothing ->
                            []

                contextWithDataRefs =
                    { context | dataTypeReferenceRanges = context.dataTypeReferenceRanges ++ dataRefs }
            in
            if functionName == "head" then
                ( [], { contextWithDataRefs | inHeadFunction = True } )

            else if functionName == "data" then
                -- Track the data function's type signature for updating Data -> Ephemeral
                case function.signature of
                    Just signatureNode ->
                        let
                            signature =
                                Node.value signatureNode

                            typeAnnotation =
                                signature.typeAnnotation

                            signatureStr =
                                typeAnnotationToString (Node.value typeAnnotation)
                        in
                        ( []
                        , { contextWithDataRefs
                            | dataFunctionSignatureRange = Just (Node.range typeAnnotation)
                            , dataFunctionSignature = Just signatureStr
                          }
                        )

                    Nothing ->
                        ( [], contextWithDataRefs )

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
                ( [], { contextWithDataRefs | appParamName = maybeAppParam } )

            else
                -- Analyze non-special functions as potential helpers
                -- This allows us to track which fields they access when called with app.data
                let
                    helperAnalysis =
                        analyzeHelperFunction function

                    contextWithHelper =
                        case helperAnalysis of
                            Just analysis ->
                                { contextWithDataRefs
                                    | helperFunctions =
                                        Dict.insert functionName analysis contextWithDataRefs.helperFunctions
                                }

                            Nothing ->
                                contextWithDataRefs
                in
                ( [], contextWithHelper )

        Declaration.AliasDeclaration typeAlias ->
            let
                typeName =
                    Node.value typeAlias.name
            in
            if typeName == "Ephemeral" then
                -- Ephemeral type already exists - transformation was already applied
                ( [], { context | hasEphemeralType = True } )

            else if typeName == "Data" then
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

                            endRow =
                                (Node.range node).end.row
                        in
                        ( []
                        , { context
                            | dataTypeRange = Just (Node.range node)
                            , dataTypeFields = fields
                            , dataTypeEndRow = endRow
                          }
                        )

                    _ ->
                        ( [], context )

            else
                ( [], context )

        _ ->
            ( [], context )


declarationExitVisitor : Node Declaration -> Context -> ( List (Error {}), Context )
declarationExitVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                functionName =
                    function.declaration
                        |> Node.value
                        |> .name
                        |> Node.value
            in
            if functionName == "head" then
                ( [], { context | inHeadFunction = False } )

            else
                ( [], context )

        _ ->
            ( [], context )


expressionEnterVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionEnterVisitor node context =
    let
        -- Track where Data is used as a record constructor (needs to become Ephemeral)
        contextWithDataConstructorCheck =
            case Node.value node of
                Expression.FunctionOrValue [] "Data" ->
                    { context | dataConstructorRanges = Node.range node :: context.dataConstructorRanges }

                _ ->
                    context

        -- Track entering freeze calls and check for app.data passed in client context
        contextWithFreezeTracking =
            case Node.value node of
                Expression.Application (functionNode :: args) ->
                    case ModuleNameLookupTable.moduleNameFor contextWithDataConstructorCheck.lookupTable functionNode of
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "freeze" ->
                                    -- Entering freeze context - we don't care about tracking inside
                                    { contextWithDataConstructorCheck
                                        | inFreezeCall = True
                                    }

                                _ ->
                                    -- Check for app.data passed as whole in CLIENT context
                                    checkAppDataPassedToHelper contextWithDataConstructorCheck functionNode args

                        _ ->
                            -- Check for app.data passed as whole in CLIENT context
                            checkAppDataPassedToHelper contextWithDataConstructorCheck functionNode args

                _ ->
                    contextWithDataConstructorCheck

        -- Track field access patterns
        contextWithFieldTracking =
            trackFieldAccess node contextWithFreezeTracking
    in
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


{-| Track field access on app.data
-}
trackFieldAccess : Node Expression -> Context -> Context
trackFieldAccess node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            if isAppDataAccess innerExpr context then
                addFieldAccess fieldName context

            else
                case Node.value innerExpr of
                    Expression.RecordAccess innerInner (Node _ topLevelField) ->
                        if isAppDataAccess innerInner context then
                            addFieldAccess topLevelField context

                        else
                            context

                    _ ->
                        context

        Expression.LetExpression letBlock ->
            let
                newBindings =
                    letBlock.declarations
                        |> List.foldl
                            (\declNode acc ->
                                case Node.value declNode of
                                    Expression.LetFunction letFn ->
                                        let
                                            fnDecl =
                                                Node.value letFn.declaration
                                        in
                                        case fnDecl.arguments of
                                            [] ->
                                                if isAppDataExpression fnDecl.expression context then
                                                    Set.insert (Node.value fnDecl.name) acc

                                                else
                                                    acc

                                            _ ->
                                                acc

                                    Expression.LetDestructuring pattern expr ->
                                        if isAppDataExpression expr context then
                                            extractPatternNames pattern
                                                |> Set.union acc

                                        else
                                            acc
                            )
                            context.appDataBindings
            in
            { context | appDataBindings = newBindings }

        -- Pipe operator with accessor: app.data |> .field
        -- We CAN track this! The RecordAccessFunction contains the field name
        Expression.OperatorApplication "|>" _ leftExpr rightExpr ->
            if isAppDataExpression leftExpr context then
                case Node.value rightExpr of
                    Expression.RecordAccessFunction accessorName ->
                        -- Extract field name (RecordAccessFunction stores ".fieldName")
                        let
                            fieldName =
                                String.dropLeft 1 accessorName
                        in
                        -- Track this specific field access
                        addFieldAccess fieldName context

                    _ ->
                        context

            else
                context

        -- Backward pipe operator with accessor: .field <| app.data
        -- Semantically equivalent to app.data |> .field and .field app.data
        Expression.OperatorApplication "<|" _ leftExpr rightExpr ->
            if isAppDataExpression rightExpr context then
                case Node.value leftExpr of
                    Expression.RecordAccessFunction accessorName ->
                        -- Extract field name (RecordAccessFunction stores ".fieldName")
                        let
                            fieldName =
                                String.dropLeft 1 accessorName
                        in
                        -- Track this specific field access
                        addFieldAccess fieldName context

                    _ ->
                        context

            else
                context

        -- Accessor function application: .field app.data
        -- This is semantically equivalent to app.data |> .field
        -- We can track the specific field being accessed
        Expression.Application [ functionNode, argNode ] ->
            case Node.value functionNode of
                Expression.RecordAccessFunction accessorName ->
                    if isAppDataExpression argNode context then
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
            if isAppDataExpression caseBlock.expression context then
                if context.inFreezeCall || context.inHeadFunction then
                    -- In ephemeral context, we don't care
                    context

                else
                    -- In client context, try to extract record pattern fields
                    let
                        maybeFieldSets =
                            caseBlock.cases
                                |> List.map (\( pattern, _ ) -> extractRecordPatternFields pattern)

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
                        markAllFieldsAsPersistent context

            else
                context

        _ ->
            context


{-| Check if a function node is a call to View.freeze.
Uses the ModuleNameLookupTable to handle all import styles:
- `View.freeze` (qualified)
- `freeze` (if imported directly with `exposing (freeze)`)
- `V.freeze` (if imported with alias `as V`)
-}
isViewFreezeCall : Node Expression -> Context -> Bool
isViewFreezeCall functionNode context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "freeze" ->
            -- Check if this "freeze" resolves to the View module
            ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode == Just [ "View" ]

        _ ->
            False


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

        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        _ ->
            False


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


containsAppDataExpression : Node Expression -> Context -> Bool
containsAppDataExpression node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] varName ->
                    -- Check if varName matches the App parameter name (e.g., "app", "static")
                    if context.appParamName == Just varName then
                        True

                    else
                        containsAppDataExpression innerExpr context

                _ ->
                    containsAppDataExpression innerExpr context

        Expression.RecordAccess _ _ ->
            False

        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        Expression.Application ((functionNode :: _) as exprs) ->
            -- Check if this is a View.freeze call using the lookup table
            -- This handles all import styles: View.freeze, qualified imports, aliases
            if isViewFreezeCall functionNode context then
                -- View.freeze calls are ephemeral context - don't worry about app.data inside them
                False

            else
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

        _ ->
            False


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


{-| Try to extract field names from a record pattern.
Returns Just (Set String) if the pattern is a record pattern (or variation),
Nothing if it's a variable pattern or other untrackable pattern.

Trackable patterns:

  - `{ title, body }` -> Just {"title", "body"}
  - `({ title })` -> Just {"title"} (parenthesized)
  - `{ title } as data` -> Just {"title"} (as pattern wrapping record)
  - `_` -> Just {} (wildcard - no fields used)

Untrackable patterns:

  - `data` -> Nothing (variable captures whole record)
  - `Data title body` -> Nothing (constructor pattern)

-}
extractRecordPatternFields : Node Pattern -> Maybe (Set String)
extractRecordPatternFields node =
    case Node.value node of
        Pattern.RecordPattern fields ->
            Just (fields |> List.map Node.value |> Set.fromList)

        Pattern.ParenthesizedPattern inner ->
            extractRecordPatternFields inner

        Pattern.AsPattern inner _ ->
            -- { title } as data - we can track the record fields
            extractRecordPatternFields inner

        Pattern.AllPattern ->
            -- Wildcard `_` matches but uses no fields
            Just Set.empty

        Pattern.VarPattern _ ->
            -- Variable pattern captures the whole record - can't track
            Nothing

        _ ->
            -- Constructor patterns, tuples, etc. - can't track
            Nothing


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


{-| Check if app.data is passed as a whole to a function.

In CLIENT context: track as pending helper call for field usage analysis.
In FREEZE context: we don't care (it's ephemeral).

Instead of immediately resolving helper lookups (which may fail if the helper
is declared after the call site), we store pending helper calls to be resolved
in finalEvaluation after all helper functions have been analyzed.

  - Just funcName = local function with app.data passed DIRECTLY, will look up in helperFunctions later
  - Nothing = can't track (qualified function, app.data wrapped in list/tuple/etc.)

-}
checkAppDataPassedToHelper : Context -> Node Expression -> List (Node Expression) -> Context
checkAppDataPassedToHelper context functionNode args =
    let
        -- Check for DIRECT app.data arguments (can potentially use helper analysis)
        -- vs WRAPPED app.data arguments (list, tuple, etc. - can't track)
        ( directAppDataArgs, wrappedAppDataArgs ) =
            args
                |> List.foldl
                    (\arg ( direct, wrapped ) ->
                        case Node.value arg of
                            -- Check if this is app.data directly (not app.data.field)
                            Expression.RecordAccess innerExpr (Node _ fieldName) ->
                                if fieldName == "data" && isAppDataExpression arg context then
                                    -- This IS app.data passed directly - potentially trackable
                                    ( arg :: direct, wrapped )

                                else if isAppDataAccess innerExpr context then
                                    -- This is app.data.field - trackable via normal field tracking, skip
                                    ( direct, wrapped )

                                else if containsAppDataExpression innerExpr context then
                                    -- app.data is nested inside - untrackable
                                    ( direct, arg :: wrapped )

                                else
                                    ( direct, wrapped )

                            -- If the arg is a function call that contains app.data,
                            -- we can't track which fields are used - untrackable
                            Expression.Application innerArgs ->
                                if List.any (\a -> containsAppDataExpression a context) innerArgs then
                                    ( direct, arg :: wrapped )

                                else
                                    ( direct, wrapped )

                            -- Variable bound to app.data passed directly
                            Expression.FunctionOrValue [] varName ->
                                if Set.member varName context.appDataBindings then
                                    ( arg :: direct, wrapped )

                                else
                                    ( direct, wrapped )

                            -- Lists, tuples, etc. containing app.data - untrackable
                            _ ->
                                if containsAppDataExpression arg context then
                                    ( direct, arg :: wrapped )

                                else
                                    ( direct, wrapped )
                    )
                    ( [], [] )

        hasDirectAppData =
            not (List.isEmpty directAppDataArgs)

        hasWrappedAppData =
            not (List.isEmpty wrappedAppDataArgs)

        -- Check if this is a record accessor function application: .field app.data
        -- This is handled by trackFieldAccess, so we don't need to process it here
        isAccessorFunctionApplication =
            case Node.value functionNode of
                Expression.RecordAccessFunction _ ->
                    -- Single arg and it's app.data - this is .field app.data
                    -- which is tracked by trackFieldAccess, so skip here
                    List.length args == 1 && hasDirectAppData

                _ ->
                    False

        -- Extract function name if it's a local function
        maybeFuncName =
            case Node.value functionNode of
                Expression.FunctionOrValue [] funcName ->
                    Just funcName

                _ ->
                    Nothing
    in
    -- Skip if this is an accessor function application like .field app.data
    -- which is already handled by trackFieldAccess
    if isAccessorFunctionApplication then
        context

    else if context.inFreezeCall || context.inHeadFunction then
        -- In ephemeral context (freeze/head) - we don't care about tracking
        context

    else
        -- In client context - check if app.data is passed as a whole
        if hasWrappedAppData then
            -- app.data is wrapped in list/tuple/etc. - can't track, bail out
            { context | pendingHelperCalls = Nothing :: context.pendingHelperCalls }

        else if hasDirectAppData then
            -- app.data passed directly - may be able to track via helper analysis
            case maybeFuncName of
                Just funcName ->
                    -- Local function - store name for lookup in finalEvaluation
                    { context | pendingHelperCalls = Just funcName :: context.pendingHelperCalls }

                Nothing ->
                    -- Qualified or complex function expression - can't look up
                    { context | pendingHelperCalls = Nothing :: context.pendingHelperCalls }

        else
            context


{-| Mark all fields as persistent (safe fallback when we can't track field usage).
This adds all field names to fieldsOutsideFreeze, which means nothing will be ephemeral.
-}
markAllFieldsAsPersistent : Context -> Context
markAllFieldsAsPersistent context =
    let
        allFieldNames =
            context.dataTypeFields
                |> List.map Tuple.first
                |> Set.fromList
    in
    { context | fieldsOutsideFreeze = Set.union context.fieldsOutsideFreeze allFieldNames }


{-| Extract all ranges where "Data" appears as a type reference in a type annotation.
-}
extractDataTypeReferences : Node TypeAnnotation -> List Range
extractDataTypeReferences node =
    case Node.value node of
        TypeAnnotation.Typed (Node typeRange ( [], "Data" )) args ->
            -- Found a reference to "Data" (unqualified)
            typeRange :: List.concatMap extractDataTypeReferences args

        TypeAnnotation.Typed _ args ->
            -- Some other type, but check its arguments
            List.concatMap extractDataTypeReferences args

        TypeAnnotation.Tupled nodes ->
            List.concatMap extractDataTypeReferences nodes

        TypeAnnotation.Record fields ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, fieldType )) ->
                        extractDataTypeReferences fieldType
                    )

        TypeAnnotation.GenericRecord _ (Node _ fields) ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, fieldType )) ->
                        extractDataTypeReferences fieldType
                    )

        TypeAnnotation.FunctionTypeAnnotation left right ->
            extractDataTypeReferences left ++ extractDataTypeReferences right

        TypeAnnotation.GenericType _ ->
            []

        TypeAnnotation.Unit ->
            []


addFieldAccess : String -> Context -> Context
addFieldAccess fieldName context =
    if context.inFreezeCall then
        { context | fieldsInFreeze = Set.insert fieldName context.fieldsInFreeze }

    else if context.inHeadFunction then
        { context | fieldsInHead = Set.insert fieldName context.fieldsInHead }

    else
        { context | fieldsOutsideFreeze = Set.insert fieldName context.fieldsOutsideFreeze }


{-| Final evaluation - generate Ephemeral/Data split and ephemeralToData function.

The formula is: ephemeral = allFields - fieldsOutsideFreeze

This is the aggressive approach that aligns with the client-side transform.
Pending helper calls are resolved here against the now-complete helperFunctions dict.
If any helper call can't be resolved (unknown function or untrackable helper), we
mark all fields as persistent (safe fallback).
-}
finalEvaluation : Context -> List (Error {})
finalEvaluation context =
    -- Skip if transformation was already applied (Ephemeral type exists)
    if context.hasEphemeralType then
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

                    -- Resolve pending helper calls against the now-complete helperFunctions dict
                    -- Returns (additionalPersistentFields, shouldMarkAllFieldsAsPersistent)
                    ( resolvedHelperFields, unresolvedHelperCalls ) =
                        context.pendingHelperCalls
                            |> List.foldl
                                (\pendingCall ( fields, unresolved ) ->
                                    case pendingCall of
                                        Nothing ->
                                            -- Qualified/complex function - can't track
                                            ( fields, True )

                                        Just funcName ->
                                            case Dict.get funcName context.helperFunctions of
                                                Just analysis ->
                                                    if analysis.isTrackable then
                                                        -- Known helper with trackable field usage!
                                                        ( Set.union fields analysis.accessedFields, unresolved )

                                                    else
                                                        -- Helper uses param in untrackable ways
                                                        ( fields, True )

                                                Nothing ->
                                                    -- Unknown function - can't track which fields it uses
                                                    ( fields, True )
                                )
                                ( Set.empty, False )

                    -- Combine direct field accesses with helper-resolved fields
                    effectiveFieldsOutsideFreeze =
                        if unresolvedHelperCalls then
                            -- Can't track, so assume ALL fields are used outside freeze (safe fallback)
                            allFieldNames

                        else
                            Set.union context.fieldsOutsideFreeze resolvedHelperFields

                    -- Ephemeral fields: all fields that are NOT used outside freeze/head
                    -- This is the aggressive formula, aligned with client-side transform
                    ephemeralFields =
                        allFieldNames
                            |> Set.filter (\f -> not (Set.member f effectiveFieldsOutsideFreeze))

                    -- Persistent fields for the new Data type
                    persistentFieldDefs =
                        context.dataTypeFields
                            |> List.filter (\( name, _ ) -> not (Set.member name ephemeralFields))
                in
                if Set.isEmpty ephemeralFields then
                    -- No ephemeral fields, nothing to transform
                    []

                else
                    -- Generate the transformation:
                    -- 1. Rename Data to Ephemeral
                    -- 2. Add new Data type with only persistent fields
                    -- 3. Add ephemeralToData function
                    let
                        -- Generate Ephemeral type alias (same as original Data)
                        ephemeralTypeAlias =
                            "type alias Ephemeral =\n    { "
                                ++ (context.dataTypeFields
                                        |> List.map
                                            (\( name, typeNode ) ->
                                                name ++ " : " ++ typeAnnotationToString (Node.value typeNode)
                                            )
                                        |> String.join "\n    , "
                                   )
                                ++ "\n    }"

                        -- Generate new Data type alias (persistent fields only)
                        newDataTypeAlias =
                            if List.isEmpty persistentFieldDefs then
                                "type alias Data =\n    {}"

                            else
                                "type alias Data =\n    { "
                                    ++ (persistentFieldDefs
                                            |> List.map
                                                (\( name, typeNode ) ->
                                                    name ++ " : " ++ typeAnnotationToString (Node.value typeNode)
                                                )
                                            |> String.join "\n    , "
                                       )
                                    ++ "\n    }"

                        -- Generate ephemeralToData function
                        ephemeralToDataFn =
                            if List.isEmpty persistentFieldDefs then
                                "ephemeralToData : Ephemeral -> Data\nephemeralToData _ =\n    {}"

                            else
                                "ephemeralToData : Ephemeral -> Data\nephemeralToData ephemeral =\n    { "
                                    ++ (persistentFieldDefs
                                            |> List.map (\( name, _ ) -> name ++ " = ephemeral." ++ name)
                                            |> String.join "\n    , "
                                       )
                                    ++ "\n    }"

                        -- Full replacement: Ephemeral + Data + ephemeralToData
                        fullReplacement =
                            ephemeralTypeAlias
                                ++ "\n\n\n"
                                ++ newDataTypeAlias
                                ++ "\n\n\n"
                                ++ ephemeralToDataFn

                        -- Update data function signature: Data -> Ephemeral
                        dataSignatureFix =
                            case ( context.dataFunctionSignatureRange, context.dataFunctionSignature ) of
                                ( Just sigRange, Just sigStr ) ->
                                    -- Replace "Data" with "Ephemeral" in the signature
                                    -- The data function returns BackendTask ... Data, we need it to return Ephemeral
                                    let
                                        updatedSig =
                                            String.replace " Data" " Ephemeral" sigStr
                                    in
                                    if updatedSig /= sigStr then
                                        [ Rule.errorWithFix
                                            { message = "Server codemod: update data function return type"
                                            , details =
                                                [ "Changing return type from Data to Ephemeral."
                                                , "The data function now returns Ephemeral (full type) for rendering."
                                                ]
                                            }
                                            sigRange
                                            [ Review.Fix.replaceRangeBy sigRange updatedSig ]
                                        ]

                                    else
                                        []

                                _ ->
                                    []

                        -- Fix Data constructor uses (e.g., map4 Data -> map4 Ephemeral)
                        dataConstructorFixes =
                            context.dataConstructorRanges
                                |> List.map
                                    (\constructorRange ->
                                        Rule.errorWithFix
                                            { message = "Server codemod: update Data constructor to Ephemeral"
                                            , details =
                                                [ "Changing Data to Ephemeral in record constructor usage."
                                                , "The full record type is now called Ephemeral."
                                                ]
                                            }
                                            constructorRange
                                            [ Review.Fix.replaceRangeBy constructorRange "Ephemeral" ]
                                    )

                        -- Fix Data type references in function signatures (e.g., App Data -> App Ephemeral)
                        dataTypeReferenceFixes =
                            context.dataTypeReferenceRanges
                                |> List.map
                                    (\refRange ->
                                        Rule.errorWithFix
                                            { message = "Server codemod: update Data type reference to Ephemeral"
                                            , details =
                                                [ "Changing Data to Ephemeral in type signature."
                                                , "The server uses Ephemeral (full type) for views."
                                                ]
                                            }
                                            refRange
                                            [ Review.Fix.replaceRangeBy refRange "Ephemeral" ]
                                    )

                        -- Fix module exports to include Ephemeral
                        exportFix =
                            case context.dataExportRange of
                                Just exportRange ->
                                    -- Insert ", Ephemeral" after "Data" in exports
                                    [ Rule.errorWithFix
                                        { message = "Server codemod: export Ephemeral type"
                                        , details =
                                            [ "Adding Ephemeral to module exports."
                                            , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                            ]
                                        }
                                        exportRange
                                        [ Review.Fix.insertAt exportRange.end ", Ephemeral, ephemeralToData" ]
                                    ]

                                Nothing ->
                                    []
                    in
                    Rule.errorWithFix
                        { message = "Server codemod: split Data into Ephemeral and Data"
                        , details =
                            [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                            , "Ephemeral fields: " ++ String.join ", " (Set.toList ephemeralFields)
                            , "Generating ephemeralToData conversion function for wire encoding."
                            ]
                        }
                        range
                        [ Review.Fix.replaceRangeBy range fullReplacement
                        ]
                        :: dataSignatureFix
                        ++ dataConstructorFixes
                        ++ dataTypeReferenceFixes
                        ++ exportFix


{-| Convert a TypeAnnotation back to string representation.
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

                leftWrapped =
                    case left of
                        TypeAnnotation.FunctionTypeAnnotation _ _ ->
                            "(" ++ leftStr ++ ")"

                        _ ->
                            leftStr
            in
            leftWrapped ++ " -> " ++ rightStr


{-| Analyze a helper function to determine which fields it accesses on its first parameter.

This enables tracking field usage when app.data is passed to a helper function.
Also handles record destructuring patterns like `renderContent { title, body } = ...`
where we know EXACTLY which fields are used.
-}
analyzeHelperFunction : Expression.Function -> Maybe HelperAnalysis
analyzeHelperFunction function =
    let
        declaration =
            Node.value function.declaration

        arguments =
            declaration.arguments

        body =
            declaration.expression
    in
    case arguments of
        firstArg :: _ ->
            case extractPatternName firstArg of
                Just paramName ->
                    -- Regular variable pattern: analyze body for field accesses
                    let
                        ( accessedFields, isTrackable ) =
                            analyzeFieldAccessesOnParam paramName body
                    in
                    Just
                        { paramName = paramName
                        , accessedFields = accessedFields
                        , isTrackable = isTrackable
                        }

                Nothing ->
                    -- First param is a pattern - check if it's a record pattern
                    case extractRecordPatternFieldsForHelper firstArg of
                        Just fields ->
                            -- Record pattern like { title, body }
                            -- We know EXACTLY which fields are accessed - no body analysis needed!
                            Just
                                { paramName = "_record_pattern_"
                                , accessedFields = fields
                                , isTrackable = True
                                }

                        Nothing ->
                            -- Other pattern (tuple, constructor, etc.) - can't track safely
                            Nothing

        [] ->
            -- No parameters, not a helper that takes data
            Nothing


{-| Extract field names from a record pattern in a helper function parameter.
-}
extractRecordPatternFieldsForHelper : Node Pattern -> Maybe (Set String)
extractRecordPatternFieldsForHelper node =
    case Node.value node of
        Pattern.RecordPattern fields ->
            Just (fields |> List.map Node.value |> Set.fromList)

        Pattern.ParenthesizedPattern inner ->
            extractRecordPatternFieldsForHelper inner

        Pattern.AsPattern inner _ ->
            extractRecordPatternFieldsForHelper inner

        _ ->
            Nothing


{-| Analyze an expression to find all field accesses on a given parameter name.
-}
analyzeFieldAccessesOnParam : String -> Node Expression -> ( Set String, Bool )
analyzeFieldAccessesOnParam paramName expr =
    analyzeFieldAccessesHelper paramName expr ( Set.empty, True )


analyzeFieldAccessesHelper : String -> Node Expression -> ( Set String, Bool ) -> ( Set String, Bool )
analyzeFieldAccessesHelper paramName node ( fields, trackable ) =
    if not trackable then
        ( fields, False )

    else
        case Node.value node of
            Expression.RecordAccess innerExpr (Node _ fieldName) ->
                case Node.value innerExpr of
                    Expression.FunctionOrValue [] varName ->
                        if varName == paramName then
                            ( Set.insert fieldName fields, trackable )

                        else
                            ( fields, trackable )

                    _ ->
                        analyzeFieldAccessesHelper paramName innerExpr ( fields, trackable )

            Expression.FunctionOrValue [] varName ->
                if varName == paramName then
                    ( fields, False )

                else
                    ( fields, trackable )

            Expression.Application exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesHelper paramName e acc)
                    ( fields, trackable )
                    exprs

            Expression.LetExpression letBlock ->
                let
                    ( declFields, declTrackable ) =
                        List.foldl
                            (\declNode acc ->
                                case Node.value declNode of
                                    Expression.LetFunction letFn ->
                                        analyzeFieldAccessesHelper paramName (Node.value letFn.declaration).expression acc

                                    Expression.LetDestructuring _ letExpr ->
                                        analyzeFieldAccessesHelper paramName letExpr acc
                            )
                            ( fields, trackable )
                            letBlock.declarations
                in
                analyzeFieldAccessesHelper paramName letBlock.expression ( declFields, declTrackable )

            Expression.IfBlock cond then_ else_ ->
                let
                    ( condFields, condTrackable ) =
                        analyzeFieldAccessesHelper paramName cond ( fields, trackable )

                    ( thenFields, thenTrackable ) =
                        analyzeFieldAccessesHelper paramName then_ ( condFields, condTrackable )
                in
                analyzeFieldAccessesHelper paramName else_ ( thenFields, thenTrackable )

            Expression.CaseExpression caseBlock ->
                let
                    caseOnParam =
                        case Node.value caseBlock.expression of
                            Expression.FunctionOrValue [] varName ->
                                varName == paramName

                            _ ->
                                False

                    ( exprFields, exprTrackable ) =
                        if caseOnParam then
                            ( fields, False )

                        else
                            analyzeFieldAccessesHelper paramName caseBlock.expression ( fields, trackable )
                in
                List.foldl
                    (\( _, caseExpr ) acc -> analyzeFieldAccessesHelper paramName caseExpr acc)
                    ( exprFields, exprTrackable )
                    caseBlock.cases

            Expression.LambdaExpression lambda ->
                let
                    shadowsParam =
                        lambda.args
                            |> List.any
                                (\arg ->
                                    case extractPatternName arg of
                                        Just name ->
                                            name == paramName

                                        Nothing ->
                                            False
                                )
                in
                if shadowsParam then
                    ( fields, trackable )

                else
                    analyzeFieldAccessesHelper paramName lambda.expression ( fields, trackable )

            Expression.OperatorApplication _ _ left right ->
                let
                    ( leftFields, leftTrackable ) =
                        analyzeFieldAccessesHelper paramName left ( fields, trackable )
                in
                analyzeFieldAccessesHelper paramName right ( leftFields, leftTrackable )

            Expression.ParenthesizedExpression inner ->
                analyzeFieldAccessesHelper paramName inner ( fields, trackable )

            Expression.TupledExpression exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesHelper paramName e acc)
                    ( fields, trackable )
                    exprs

            Expression.ListExpr exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesHelper paramName e acc)
                    ( fields, trackable )
                    exprs

            Expression.RecordExpr recordSetters ->
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesHelper paramName valueExpr acc
                    )
                    ( fields, trackable )
                    recordSetters

            Expression.RecordUpdateExpression (Node _ varName) recordSetters ->
                let
                    ( updateFields, updateTrackable ) =
                        if varName == paramName then
                            ( fields, False )

                        else
                            ( fields, trackable )
                in
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesHelper paramName valueExpr acc
                    )
                    ( updateFields, updateTrackable )
                    recordSetters

            Expression.Negation inner ->
                analyzeFieldAccessesHelper paramName inner ( fields, trackable )

            _ ->
                ( fields, trackable )
