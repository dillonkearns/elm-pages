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
import Pages.Review.PersistentFieldTracking as PersistentFieldTracking
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


{-| Analysis of a helper function's field usage on its first parameter.
-}
type alias HelperAnalysis =
    PersistentFieldTracking.HelperAnalysis


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

    -- Import aliases for Html and Html.Attributes (for freeze wrapping)
    , htmlAlias : Maybe ModuleName
    , htmlAttributesAlias : Maybe ModuleName

    -- Track last import row for inserting new imports
    , lastImportRow : Int
    }


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.ServerDataTransform" initialContext
        |> Rule.providesFixesForModuleRule
        |> Rule.withImportVisitor importVisitor
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
            , htmlAlias = Nothing
            , htmlAttributesAlias = Nothing
            , lastImportRow = 0
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


{-| Track Html and Html.Attributes import aliases and last import row.
-}
importVisitor : Node Import -> Context -> ( List (Rule.Error {}), Context )
importVisitor node context =
    let
        import_ =
            Node.value node

        moduleName =
            Node.value import_.moduleName

        -- Track the last import row for inserting new imports
        importEndRow =
            (Node.range node).end.row

        contextWithImportRow =
            { context | lastImportRow = max context.lastImportRow importEndRow }
    in
    if moduleName == [ "Html" ] then
        ( []
        , { contextWithImportRow
            | htmlAlias =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "Html" ]
                    |> Just
          }
        )

    else if moduleName == [ "Html", "Attributes" ] then
        ( []
        , { contextWithImportRow
            | htmlAttributesAlias =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "Html", "Attributes" ]
                    |> Just
          }
        )

    else
        ( [], contextWithImportRow )


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
                                PersistentFieldTracking.typeAnnotationToString (Node.value typeAnnotation)
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
                            |> Maybe.andThen PersistentFieldTracking.extractPatternName
                in
                ( [], { contextWithDataRefs | appParamName = maybeAppParam } )

            else
                -- Analyze non-special functions as potential helpers
                -- This allows us to track which fields they access when called with app.data
                let
                    helperAnalysis =
                        PersistentFieldTracking.analyzeHelperFunction function

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

        -- Track entering freeze calls, check for app.data passed in client context,
        -- and handle freeze wrapping
        ( freezeErrors, contextWithFreezeTracking ) =
            case Node.value node of
                Expression.Application (functionNode :: args) ->
                    case ModuleNameLookupTable.moduleNameFor contextWithDataConstructorCheck.lookupTable functionNode of
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "freeze" ->
                                    -- Handle View.freeze call - wrap argument if not already wrapped
                                    let
                                        ( errors, newContext ) =
                                            handleViewFreezeWrapping node functionNode args contextWithDataConstructorCheck
                                    in
                                    ( errors
                                    , { newContext | inFreezeCall = True }
                                    )

                                _ ->
                                    -- Check for app.data passed as whole in CLIENT context
                                    ( [], checkAppDataPassedToHelper contextWithDataConstructorCheck functionNode args )

                        _ ->
                            -- Check for app.data passed as whole in CLIENT context
                            ( [], checkAppDataPassedToHelper contextWithDataConstructorCheck functionNode args )

                _ ->
                    ( [], contextWithDataConstructorCheck )

        -- Track field access patterns
        contextWithFieldTracking =
            trackFieldAccess node contextWithFreezeTracking
    in
    ( freezeErrors, contextWithFieldTracking )


{-| Handle View.freeze calls - wrap the argument with data-static if not already wrapped.
-}
handleViewFreezeWrapping : Node Expression -> Node Expression -> List (Node Expression) -> Context -> ( List (Error {}), Context )
handleViewFreezeWrapping applicationNode functionNode args context =
    case args of
        argNode :: [] ->
            -- Unwrap ParenthesizedExpression if present to get the inner expression
            let
                innerNode =
                    unwrapParenthesizedExpression argNode

                -- Check if the original argument is already parenthesized
                isParenthesized =
                    isParenthesizedExpression argNode
            in
            -- Check if the argument is already wrapped with data-static
            if isAlreadyWrappedWithDataStatic innerNode then
                -- Already wrapped, no transformation needed (base case)
                ( [], context )

            else
                -- Generate the wrapping fix
                let
                    htmlPrefix =
                        context.htmlAlias
                            |> Maybe.map (String.join ".")
                            |> Maybe.withDefault "Html"

                    attrPrefix =
                        context.htmlAttributesAlias
                            |> Maybe.map (String.join ".")
                            |> Maybe.withDefault "Html.Attributes"

                    -- Check if we need to add imports
                    needsHtmlImport =
                        context.htmlAlias == Nothing

                    needsHtmlAttributesImport =
                        context.htmlAttributesAlias == Nothing

                    -- Build import string (Html first, then Html.Attributes for alphabetical order)
                    importsToAdd =
                        (if needsHtmlImport then
                            "import Html\n"

                         else
                            ""
                        )
                            ++ (if needsHtmlAttributesImport then
                                    "import Html.Attributes\n"

                                else
                                    ""
                               )

                    -- Import fixes - insert after the last import
                    importFixes =
                        if String.isEmpty importsToAdd then
                            []

                        else
                            [ Review.Fix.insertAt { row = context.lastImportRow + 1, column = 1 } importsToAdd ]

                    -- Use the inner expression's range, not the parenthesized wrapper
                    innerRange =
                        Node.range innerNode

                    -- We'll wrap it with: Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ <arg> ]
                    -- Need to add outer parentheses if not already parenthesized
                    ( wrapperPrefix, wrapperSuffix ) =
                        if isParenthesized then
                            -- Original had parentheses, we use the inner range and add just the wrapper
                            ( htmlPrefix
                                ++ ".div [ "
                                ++ attrPrefix
                                ++ ".attribute \"data-static\" \"__STATIC__\" ] [ "
                            , " ]"
                            )

                        else
                            -- Original didn't have parentheses, we need to add them
                            ( "("
                                ++ htmlPrefix
                                ++ ".div [ "
                                ++ attrPrefix
                                ++ ".attribute \"data-static\" \"__STATIC__\" ] [ "
                            , " ])"
                            )

                    wrapperFixes =
                        [ Review.Fix.insertAt innerRange.start wrapperPrefix
                        , Review.Fix.insertAt innerRange.end wrapperSuffix
                        ]

                    -- Combine import fixes with wrapper fixes
                    fix =
                        importFixes ++ wrapperFixes
                in
                ( [ Rule.errorWithFix
                        { message = "Server codemod: wrap freeze argument with data-static"
                        , details =
                            [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                            ]
                        }
                        (Node.range applicationNode)
                        fix
                  ]
                , context
                )

        _ ->
            -- Not a single-argument application, ignore
            ( [], context )


{-| Check if an expression is a ParenthesizedExpression.
-}
isParenthesizedExpression : Node Expression -> Bool
isParenthesizedExpression node =
    case Node.value node of
        Expression.ParenthesizedExpression _ ->
            True

        _ ->
            False


{-| Unwrap ParenthesizedExpression to get the inner expression.
-}
unwrapParenthesizedExpression : Node Expression -> Node Expression
unwrapParenthesizedExpression node =
    case Node.value node of
        Expression.ParenthesizedExpression innerNode ->
            unwrapParenthesizedExpression innerNode

        _ ->
            node


{-| Check if an expression is already wrapped with Html.div with data-static attribute.
This is the base case to prevent infinite loops.

Looks for pattern:
Html.div [ Html.Attributes.attribute "data-static" "..." ] [ ... ]

-}
isAlreadyWrappedWithDataStatic : Node Expression -> Bool
isAlreadyWrappedWithDataStatic node =
    case Node.value node of
        Expression.Application (functionNode :: attrListNode :: _) ->
            -- Check if function is Html.div (or aliased)
            case Node.value functionNode of
                Expression.FunctionOrValue moduleName "div" ->
                    -- Could be Html.div, H.div, etc.
                    -- Check if the attribute list contains data-static
                    containsDataStaticAttribute attrListNode

                _ ->
                    False

        _ ->
            False


{-| Check if an attribute list expression contains a data-static attribute.
-}
containsDataStaticAttribute : Node Expression -> Bool
containsDataStaticAttribute node =
    case Node.value node of
        Expression.ListExpr items ->
            List.any isDataStaticAttribute items

        _ ->
            False


{-| Check if an expression is an Html.Attributes.attribute "data-static" "..." call.
-}
isDataStaticAttribute : Node Expression -> Bool
isDataStaticAttribute node =
    case Node.value node of
        Expression.Application (functionNode :: args) ->
            case Node.value functionNode of
                Expression.FunctionOrValue _ "attribute" ->
                    -- Check if first argument is "data-static"
                    case args of
                        (Node _ (Expression.Literal "data-static")) :: _ ->
                            True

                        _ ->
                            False

                _ ->
                    False

        _ ->
            False


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
        Expression.RecordAccess _ _ ->
            case PersistentFieldTracking.extractAppDataFieldName node context.appParamName context.appDataBindings of
                Just fieldName ->
                    addFieldAccess fieldName context

                Nothing ->
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
                                                if isAppDataAccess fnDecl.expression context then
                                                    Set.insert (Node.value fnDecl.name) acc

                                                else
                                                    acc

                                            _ ->
                                                acc

                                    Expression.LetDestructuring pattern expr ->
                                        if isAppDataAccess expr context then
                                            PersistentFieldTracking.extractPatternNames pattern
                                                |> Set.union acc

                                        else
                                            acc
                            )
                            context.appDataBindings
            in
            { context | appDataBindings = newBindings }

        -- Pipe operators with accessor: app.data |> .field or .field <| app.data
        Expression.OperatorApplication op _ leftExpr rightExpr ->
            case extractAppDataPipeAccessorField op leftExpr rightExpr context of
                Just fieldName ->
                    addFieldAccess fieldName context

                Nothing ->
                    context

        -- Accessor function application: .field app.data
        -- This is semantically equivalent to app.data |> .field
        Expression.Application [ functionNode, argNode ] ->
            case PersistentFieldTracking.extractAppDataAccessorApplicationField functionNode argNode context.appParamName context.appDataBindings of
                Just fieldName ->
                    addFieldAccess fieldName context

                Nothing ->
                    context

        -- Case expression on app.data: case app.data of {...}
        -- Track record patterns, bail out on variable patterns
        Expression.CaseExpression caseBlock ->
            if isAppDataAccess caseBlock.expression context then
                if context.inFreezeCall || context.inHeadFunction then
                    -- In ephemeral context, we don't care
                    context

                else
                    -- In client context, extract fields from patterns
                    case PersistentFieldTracking.extractCasePatternFields caseBlock.cases of
                        PersistentFieldTracking.TrackableFields allFields ->
                            Set.foldl addFieldAccess context allFields

                        PersistentFieldTracking.UntrackablePattern ->
                            markAllFieldsAsPersistent context

            else
                context

        _ ->
            context


{-| Check if a function node is a call to View.freeze.
-}
isViewFreezeCall : Node Expression -> Context -> Bool
isViewFreezeCall functionNode context =
    PersistentFieldTracking.isViewFreezeCall functionNode context.lookupTable


isAppDataAccess : Node Expression -> Context -> Bool
isAppDataAccess node context =
    PersistentFieldTracking.isAppDataAccess node context.appParamName context.appDataBindings




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


{-| Check if app.data is passed as a whole to a function.

In CLIENT context: track as pending helper call for field usage analysis.
In FREEZE context: we don't care (it's ephemeral).

Uses shared classifyAppDataArguments from PersistentFieldTracking.

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
        -- In ephemeral context (freeze/head) - we don't care about tracking
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
                        PersistentFieldTracking.resolvePendingHelperCalls
                            context.pendingHelperCalls
                            context.helperFunctions

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
                                                name ++ " : " ++ PersistentFieldTracking.typeAnnotationToString (Node.value typeNode)
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
                                                    name ++ " : " ++ PersistentFieldTracking.typeAnnotationToString (Node.value typeNode)
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
