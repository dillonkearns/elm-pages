module Pages.Review.StaticViewTransform exposing (rule)

{-| This rule transforms frozen view render calls into inlined lazy thunks in the client
bundle. This enables dead-code elimination of the frozen view rendering dependencies
(markdown parsers, syntax highlighters, etc.) while preserving the pre-rendered
HTML for adoption by the virtual-dom.

## Transformations

    -- View.freeze (user-defined in View.elm):
    View.freeze (heavyRender data)
    -- becomes:
    Html.Lazy.lazy (\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable

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

The inlined lazy thunk uses a magic string prefix "__ELM_PAGES_STATIC__" that
the virtual-dom codemod detects at runtime to adopt pre-rendered HTML.

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
import Pages.Review.TaintTracking as Taint
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
    , htmlLazyImport : HtmlLazyImport
    , virtualDomImported : Bool
    , htmlStyledAlias : Maybe ModuleName
    , lastImportRow : Int
    , staticIndex : Int

    -- Shared field tracking state (embedded from PersistentFieldTracking)
    -- This contains: clientUsedFields, inFreezeCall, inHeadFunction, appDataBindings,
    -- appParamName, helperFunctions, pendingHelperCalls, dataTypeFields, markAllFieldsAsUsed
    , sharedState : PersistentFieldTracking.SharedFieldTrackingState

    -- Client-specific tracking for current function name
    , currentFunctionName : Maybe String

    -- Per-function field tracking (for non-conventional head function names)
    -- Maps function name -> fields accessed outside freeze in that function
    -- Used in finalEvaluation to exclude fields accessed by the actual head function
    , perFunctionClientFields : Dict String (Set String)

    -- Field-specific binding tracking (for let bindings like `let title = app.data.title`)
    -- Maps variable name -> field name from app.data
    -- When a variable is used in client context, we mark its field as client-used
    , fieldBindings : Dict String String

    -- Ranges of expressions that are RHS of field bindings (to skip in normal tracking)
    -- These are tracked via the variable usage, not the direct field access
    , fieldBindingRanges : Set ( ( Int, Int ), ( Int, Int ) )

    -- Track if Data is used as a record constructor function
    -- (e.g., `map4 Data arg1 arg2 arg3 arg4`)
    -- If true, we can't transform the type alias without breaking the constructor
    , dataUsedAsConstructor : Bool

    -- Data type location for transformation
    , dataTypeRange : Maybe Range
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

    -- Model parameter name from view function (third parameter, typically "model")
    , modelParamName : Maybe String

    -- Taint tracking for model-derived bindings (used to de-optimize freeze calls)
    , taintBindings : Taint.Bindings

    -- Tainted context depth: tracks when we're inside a conditional (if/case) that
    -- depends on model. When > 0, we're in a tainted context and should skip transforms.
    , taintedContextDepth : Int

    -- Track if NarrowedData type alias already exists (to prevent infinite fix loop)
    , narrowedDataExists : Bool

    -- Helpers called with app.data inside freeze context
    -- These can have their type annotations updated from Data to Ephemeral
    , helpersCalledInFreeze : Set String

    -- Ranges where "Data" appears in helper type annotations (maps function name -> list of ranges)
    -- Used to replace Data with Ephemeral for freeze-only helpers
    , helperDataTypeRanges : Dict String (List Range)
    }


type HtmlLazyImport
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
        |> Rule.withCaseBranchEnterVisitor caseBranchEnterVisitor
        |> Rule.withCaseBranchExitVisitor caseBranchExitVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation
        |> Rule.fromModuleRuleSchema


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable moduleName () ->
            { lookupTable = lookupTable
            , moduleName = moduleName
            , htmlLazyImport = NotImported
            , virtualDomImported = False
            , htmlStyledAlias = Nothing
            , lastImportRow = 2
            , staticIndex = 0
            , sharedState = PersistentFieldTracking.emptySharedState
            , currentFunctionName = Nothing
            , perFunctionClientFields = Dict.empty
            , fieldBindings = Dict.empty
            , fieldBindingRanges = Set.empty
            , dataUsedAsConstructor = False
            , dataTypeRange = Nothing
            , dataTypeDeclarationEndRow = 0
            , appDataTypeRanges = []
            , headFunctionBodyRange = Nothing
            , dataFunctionBodyRange = Nothing
            , routeBuilderHeadFn = Nothing
            , routeBuilderDataFn = Nothing
            , routeBuilderFound = False
            , modelParamName = Nothing
            , taintBindings = Taint.emptyBindings
            , taintedContextDepth = 0
            , narrowedDataExists = False
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
    if moduleName == [ "Html", "Lazy" ] then
        ( []
        , { context
            | htmlLazyImport =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "Html", "Lazy" ]
                    |> ImportedAs
            , lastImportRow = max context.lastImportRow importEndRow
          }
        )

    else if moduleName == [ "VirtualDom" ] then
        ( []
        , { context
            | virtualDomImported = True
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
                    | sharedState = PersistentFieldTracking.updateOnHeadEnter contextWithAppDataRanges.sharedState
                    , headFunctionBodyRange = Just bodyRange
                  }
                )

            else if functionName == actualDataFn then
                -- Capture the data function body for potential stubbing
                -- The data function never runs on client, only at build time
                ( [], { contextWithAppDataRanges | dataFunctionBodyRange = Just bodyRange } )

            else if functionName == "view" || functionName == "init" || functionName == "update" then
                -- Extract the App parameter name from client-side functions
                -- We need to track field usage in ALL client-side functions, not just view
                -- because fields accessed in init/update also need to be in the client Data type
                --
                -- IMPORTANT: The App parameter position varies by function:
                -- - view: typically first parameter, but can vary with buildWithLocalState
                -- - init: typically third parameter (after Maybe PageUrl, Shared.Model)
                -- - update: typically third parameter (after PageUrl, Shared.Model)
                --
                -- We find the correct position by looking at the type signature for the
                -- parameter with type `App Data ActionData RouteParams`.
                let
                    arguments =
                        function.declaration
                            |> Node.value
                            |> .arguments

                    -- Try to find App parameter index from type signature
                    maybeAppParamIndex =
                        case function.signature of
                            Just (Node _ signature) ->
                                findAppParamIndex signature.typeAnnotation

                            Nothing ->
                                -- No type signature - fall back to first parameter
                                Just 0

                    maybeAppParam =
                        maybeAppParamIndex
                            |> Maybe.andThen
                                (\index ->
                                    arguments
                                        |> List.drop index
                                        |> List.head
                                )
                            |> Maybe.andThen PersistentFieldTracking.extractPatternName

                    -- Extract model parameter name only for view function
                    -- Model is the third parameter: view app shared model = ...
                    maybeModelParam =
                        if functionName == "view" then
                            arguments
                                |> List.drop 2
                                |> List.head
                                |> Maybe.andThen PersistentFieldTracking.extractPatternName

                        else
                            Nothing
                in
                let
                    updatedSharedState =
                        { clientUsedFields = contextWithAppDataRanges.sharedState.clientUsedFields
                        , inFreezeCall = contextWithAppDataRanges.sharedState.inFreezeCall
                        , inHeadFunction = contextWithAppDataRanges.sharedState.inHeadFunction
                        , appDataBindings = contextWithAppDataRanges.sharedState.appDataBindings
                        , appParamName = maybeAppParam
                        , helperFunctions = contextWithAppDataRanges.sharedState.helperFunctions
                        , pendingHelperCalls = contextWithAppDataRanges.sharedState.pendingHelperCalls
                        , dataTypeFields = contextWithAppDataRanges.sharedState.dataTypeFields
                        , markAllFieldsAsUsed = contextWithAppDataRanges.sharedState.markAllFieldsAsUsed
                        }
                in
                ( []
                , { contextWithAppDataRanges
                    | sharedState = updatedSharedState
                    , modelParamName = maybeModelParam
                  }
                )

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
                        if List.isEmpty helperAnalysis then
                            contextWithDataRanges

                        else
                            let
                                updatedSharedState =
                                    { clientUsedFields = contextWithDataRanges.sharedState.clientUsedFields
                                    , inFreezeCall = contextWithDataRanges.sharedState.inFreezeCall
                                    , inHeadFunction = contextWithDataRanges.sharedState.inHeadFunction
                                    , appDataBindings = contextWithDataRanges.sharedState.appDataBindings
                                    , appParamName = contextWithDataRanges.sharedState.appParamName
                                    , helperFunctions = Dict.insert functionName helperAnalysis contextWithDataRanges.sharedState.helperFunctions
                                    , pendingHelperCalls = contextWithDataRanges.sharedState.pendingHelperCalls
                                    , dataTypeFields = contextWithDataRanges.sharedState.dataTypeFields
                                    , markAllFieldsAsUsed = contextWithDataRanges.sharedState.markAllFieldsAsUsed
                                    }
                            in
                            { contextWithDataRanges | sharedState = updatedSharedState }
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

                            updatedSharedState =
                                { clientUsedFields = context.sharedState.clientUsedFields
                                , inFreezeCall = context.sharedState.inFreezeCall
                                , inHeadFunction = context.sharedState.inHeadFunction
                                , appDataBindings = context.sharedState.appDataBindings
                                , appParamName = context.sharedState.appParamName
                                , helperFunctions = context.sharedState.helperFunctions
                                , pendingHelperCalls = context.sharedState.pendingHelperCalls
                                , dataTypeFields = fields
                                , markAllFieldsAsUsed = context.sharedState.markAllFieldsAsUsed
                                }
                        in
                        ( []
                        , { context
                            | dataTypeRange = Just (Node.range typeAlias.typeAnnotation)
                            , sharedState = updatedSharedState
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
                ( [], { context | sharedState = PersistentFieldTracking.updateOnHeadExit context.sharedState, currentFunctionName = Nothing } )

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
                                    { contextWithRouteBuilder | sharedState = PersistentFieldTracking.updateOnFreezeEnter contextWithRouteBuilder.sharedState }

                                _ ->
                                    -- Check for app.data passed as whole in CLIENT or FREEZE context
                                    checkAppDataPassedToHelper contextWithRouteBuilder functionNode args

                        _ ->
                            -- Check for app.data passed as whole in CLIENT or FREEZE context
                            checkAppDataPassedToHelper contextWithRouteBuilder functionNode args

                -- Handle pipe operators: app.data |> fn or fn <| app.data
                -- But NOT accessor patterns like app.data |> .field (handled by trackFieldAccess)
                Expression.OperatorApplication op _ leftExpr rightExpr ->
                    case op of
                        "|>" ->
                            -- app.data |> fn  =>  fn(app.data), so fn is on the right
                            -- Skip if fn is a RecordAccessFunction (.field) - handled elsewhere
                            if isRecordAccessFunction rightExpr then
                                contextWithRouteBuilder

                            else
                                checkAppDataPassedToHelperViaPipe contextWithRouteBuilder rightExpr leftExpr

                        "<|" ->
                            -- fn <| app.data  =>  fn(app.data), so fn is on the left
                            -- Skip if fn is a RecordAccessFunction (.field) - handled elsewhere
                            if isRecordAccessFunction leftExpr then
                                contextWithRouteBuilder

                            else
                                checkAppDataPassedToHelperViaPipe contextWithRouteBuilder leftExpr rightExpr

                        _ ->
                            contextWithRouteBuilder

                _ ->
                    contextWithRouteBuilder

        -- Track field access patterns
        contextWithFieldTracking =
            trackFieldAccess node contextWithFreezeTracking

        -- Track entering tainted conditionals (if/case)
        -- When the condition/scrutinee is tainted, increment taintedContextDepth
        -- This allows us to detect View.freeze calls inside tainted conditionals
        contextWithTaintedContext =
            case Node.value node of
                Expression.IfBlock cond _ _ ->
                    let
                        taintContext =
                            { modelParamName = contextWithFieldTracking.modelParamName
                            , bindings = contextWithFieldTracking.taintBindings
                            }

                        condTaint =
                            Taint.analyzeExpressionTaint taintContext cond
                    in
                    if condTaint == Taint.Tainted then
                        { contextWithFieldTracking | taintedContextDepth = contextWithFieldTracking.taintedContextDepth + 1 }

                    else
                        contextWithFieldTracking

                Expression.CaseExpression caseBlock ->
                    let
                        taintContext =
                            { modelParamName = contextWithFieldTracking.modelParamName
                            , bindings = contextWithFieldTracking.taintBindings
                            }

                        scrutineeTaint =
                            Taint.analyzeExpressionTaint taintContext caseBlock.expression
                    in
                    if scrutineeTaint == Taint.Tainted then
                        { contextWithFieldTracking | taintedContextDepth = contextWithFieldTracking.taintedContextDepth + 1 }

                    else
                        contextWithFieldTracking

                _ ->
                    contextWithFieldTracking

        -- Track tainted bindings for let expressions
        -- When entering a let, push a new scope and add bindings from declarations
        contextWithTaintBindings =
            case Node.value node of
                Expression.LetExpression letBlock ->
                    let
                        -- Push a new scope first
                        initialScope =
                            Taint.nonemptyCons Dict.empty contextWithTaintedContext.taintBindings

                        -- Process each let declaration, accumulating bindings
                        -- Later declarations can depend on earlier ones, so we update context as we go
                        finalScope =
                            List.foldl
                                (\declNode currentBindings ->
                                    let
                                        -- Create a TaintContext with current accumulated bindings
                                        taintContext =
                                            { modelParamName = contextWithTaintedContext.modelParamName
                                            , bindings = currentBindings
                                            }

                                        newBindings =
                                            case Node.value declNode of
                                                Expression.LetFunction letFn ->
                                                    let
                                                        fnDecl =
                                                            Node.value letFn.declaration

                                                        fnName =
                                                            Node.value fnDecl.name

                                                        -- For functions with no arguments, track as binding
                                                        -- Functions with arguments are treated as pure (they're definitions)
                                                        taint =
                                                            case fnDecl.arguments of
                                                                [] ->
                                                                    Taint.analyzeExpressionTaint taintContext fnDecl.expression

                                                                _ ->
                                                                    Taint.Pure
                                                    in
                                                    [ ( fnName, taint ) ]

                                                Expression.LetDestructuring pattern expr ->
                                                    let
                                                        exprTaint =
                                                            Taint.analyzeExpressionTaint taintContext expr
                                                    in
                                                    Taint.extractBindingsFromPattern exprTaint pattern
                                    in
                                    Taint.addBindingsToScope newBindings currentBindings
                                )
                                initialScope
                                letBlock.declarations
                    in
                    { contextWithTaintedContext | taintBindings = finalScope }

                _ ->
                    contextWithTaintedContext
    in
    -- Handle the transformations
    case Node.value node of
        Expression.Application applicationExpressions ->
            case applicationExpressions of
                -- Single-argument application: View.freeze expr
                functionNode :: _ :: [] ->
                    case ModuleNameLookupTable.moduleNameFor contextWithTaintBindings.lookupTable functionNode of
                        Just [ "View" ] ->
                            handleViewFreezeCall functionNode node contextWithTaintBindings

                        _ ->
                            ( [], contextWithTaintBindings )

                _ ->
                    ( [], contextWithTaintBindings )

        _ ->
            ( [], contextWithTaintBindings )


expressionExitVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionExitVisitor node context =
    let
        -- Pop taint binding scope when exiting let expressions
        contextWithPoppedScope =
            case Node.value node of
                Expression.LetExpression _ ->
                    case Taint.nonemptyPop context.taintBindings of
                        Just popped ->
                            { context | taintBindings = popped }

                        Nothing ->
                            -- Should never happen - we always push before pop
                            context

                _ ->
                    context

        -- Track exiting tainted conditionals (if/case)
        -- Decrement taintedContextDepth when exiting a tainted conditional
        contextWithTaintedContextUpdate =
            case Node.value node of
                Expression.IfBlock cond _ _ ->
                    let
                        taintContext =
                            { modelParamName = contextWithPoppedScope.modelParamName
                            , bindings = contextWithPoppedScope.taintBindings
                            }

                        condTaint =
                            Taint.analyzeExpressionTaint taintContext cond
                    in
                    if condTaint == Taint.Tainted && contextWithPoppedScope.taintedContextDepth > 0 then
                        { contextWithPoppedScope | taintedContextDepth = contextWithPoppedScope.taintedContextDepth - 1 }

                    else
                        contextWithPoppedScope

                Expression.CaseExpression caseBlock ->
                    let
                        taintContext =
                            { modelParamName = contextWithPoppedScope.modelParamName
                            , bindings = contextWithPoppedScope.taintBindings
                            }

                        scrutineeTaint =
                            Taint.analyzeExpressionTaint taintContext caseBlock.expression
                    in
                    if scrutineeTaint == Taint.Tainted && contextWithPoppedScope.taintedContextDepth > 0 then
                        { contextWithPoppedScope | taintedContextDepth = contextWithPoppedScope.taintedContextDepth - 1 }

                    else
                        contextWithPoppedScope

                _ ->
                    contextWithPoppedScope
    in
    if PersistentFieldTracking.isExitingFreezeCall node contextWithTaintedContextUpdate.lookupTable then
        ( [], { contextWithTaintedContextUpdate | sharedState = PersistentFieldTracking.updateOnFreezeExit contextWithTaintedContextUpdate.sharedState } )

    else
        ( [], contextWithTaintedContextUpdate )


{-| Visitor for entering a case branch. Pushes a new scope and adds pattern bindings.
Pattern bindings inherit taint from the case expression.
-}
caseBranchEnterVisitor : Node Expression.CaseBlock -> ( Node Pattern, Node Expression ) -> Context -> ( List (Error {}), Context )
caseBranchEnterVisitor caseBlockNode ( patternNode, _ ) context =
    let
        caseBlock =
            Node.value caseBlockNode

        -- Analyze the case expression for taint
        taintContext =
            { modelParamName = context.modelParamName
            , bindings = context.taintBindings
            }

        caseTaint =
            Taint.analyzeExpressionTaint taintContext caseBlock.expression

        -- Extract pattern bindings with the case expression's taint
        patternBindings =
            Taint.extractBindingsFromPattern caseTaint patternNode

        -- Push a new scope and add bindings
        newScope =
            Taint.nonemptyCons Dict.empty context.taintBindings
                |> Taint.addBindingsToScope patternBindings
    in
    ( [], { context | taintBindings = newScope } )


{-| Visitor for exiting a case branch. Pops the scope.
-}
caseBranchExitVisitor : Node Expression.CaseBlock -> ( Node Pattern, Node Expression ) -> Context -> ( List (Error {}), Context )
caseBranchExitVisitor _ _ context =
    case Taint.nonemptyPop context.taintBindings of
        Just popped ->
            ( [], { context | taintBindings = popped } )

        Nothing ->
            -- Should never happen - we always push before pop
            ( [], context )


{-| Track field access on app.data and variables bound to app.data.

Uses the shared extractFieldAccess function for common patterns (RecordAccess,
OperatorApplication, Application, RecordUpdateExpression). Handles LetExpression
and CaseExpression separately as they need context-specific logic.

The client transform has additional tracking for field bindings (let title = app.data.title)
to track variable usage rather than the definition site.

-}
trackFieldAccess : Node Expression -> Context -> Context
trackFieldAccess node context =
    let
        -- Check if this expression is in a range we should skip (field binding RHS)
        -- These are tracked via the variable usage, not the definition
        nodeRange =
            rangeToComparable (Node.range node)

        isFieldBindingRHS =
            Set.member nodeRange context.fieldBindingRanges
    in
    -- First check for variable reference to a field binding (client-specific tracking)
    case Node.value node of
        Expression.FunctionOrValue [] varName ->
            case Dict.get varName context.fieldBindings of
                Just fieldName ->
                    -- This variable is bound to an app.data field
                    addFieldAccess fieldName context

                Nothing ->
                    context

        _ ->
            -- Skip field binding RHS expressions (they're tracked via variable usage)
            if isFieldBindingRHS then
                context

            else
                -- Use shared extractFieldAccess for common patterns
                case PersistentFieldTracking.extractFieldAccess node context.sharedState.appParamName context.sharedState.appDataBindings of
                    PersistentFieldTracking.FieldAccessed fieldName ->
                        addFieldAccess fieldName context

                    PersistentFieldTracking.MarkAllFieldsUsed ->
                        if context.sharedState.inFreezeCall || context.sharedState.inHeadFunction then
                            -- In ephemeral context, we don't care
                            context

                        else
                            let
                                updatedSharedState =
                                    PersistentFieldTracking.markAllFieldsAsPersistent context.sharedState
                            in
                            { context | sharedState = updatedSharedState }

                    PersistentFieldTracking.NoFieldAccess ->
                        -- Handle patterns that need context-specific logic
                        case Node.value node of
                            -- Case expression on app.data: use shared analysis
                            Expression.CaseExpression _ ->
                                if context.sharedState.inFreezeCall || context.sharedState.inHeadFunction then
                                    -- In ephemeral context, we don't care
                                    context

                                else
                                    -- Use unified case analysis from shared module
                                    case PersistentFieldTracking.analyzeCaseOnAppData node context.sharedState.appParamName context.sharedState.appDataBindings of
                                        PersistentFieldTracking.CaseTrackedFields fields ->
                                            Set.foldl addFieldAccess context fields

                                        PersistentFieldTracking.CaseAddBindings bindings ->
                                            let
                                                currentSharedState =
                                                    context.sharedState

                                                updatedSharedState =
                                                    { currentSharedState | appDataBindings = Set.union currentSharedState.appDataBindings bindings }
                                            in
                                            { context | sharedState = updatedSharedState }

                                        PersistentFieldTracking.CaseMarkAllFieldsUsed ->
                                            let
                                                updatedSharedState =
                                                    PersistentFieldTracking.markAllFieldsAsPersistent context.sharedState
                                            in
                                            { context | sharedState = updatedSharedState }

                                        PersistentFieldTracking.CaseNotOnAppData ->
                                            context

                            -- Let expressions can bind app.data to a variable, or bind specific fields
                            -- They can also define local helper functions that should be analyzed
                            Expression.LetExpression letBlock ->
                                let
                                    -- Extract let-bound helper functions using shared logic
                                    newHelpers =
                                        PersistentFieldTracking.extractLetBoundHelperFunctions
                                            letBlock.declarations
                                            context.sharedState.helperFunctions

                                    -- Client-specific: track app.data bindings and field bindings
                                    letBindingResult =
                                        letBlock.declarations
                                            |> List.foldl
                                                (\declNode acc ->
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
                                                                            { acc
                                                                                | fieldBinds = Dict.insert varName fieldName acc.fieldBinds
                                                                                , bindingRanges = Set.insert (rangeToComparable exprRange) acc.bindingRanges
                                                                            }

                                                                        Nothing ->
                                                                            if isAppDataAccess fnDecl.expression context then
                                                                                -- let d = app.data
                                                                                { acc | appBindings = Set.insert varName acc.appBindings }

                                                                            else
                                                                                acc

                                                                _ ->
                                                                    -- Has arguments - handled by extractLetBoundHelperFunctions
                                                                    acc

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
                                                                            |> Set.foldl (\name dict -> Dict.insert name name dict) acc.fieldBinds

                                                                    -- Track the range to skip
                                                                    letExprRange =
                                                                        Node.range expr
                                                                in
                                                                { acc
                                                                    | appBindings = Set.union destructuredNames acc.appBindings
                                                                    , fieldBinds = newFieldBinds
                                                                    , bindingRanges = Set.insert (rangeToComparable letExprRange) acc.bindingRanges
                                                                }

                                                            else
                                                                acc
                                                )
                                                { appBindings = context.sharedState.appDataBindings
                                                , fieldBinds = context.fieldBindings
                                                , bindingRanges = context.fieldBindingRanges
                                                }

                                    currentSharedState =
                                        context.sharedState

                                    updatedSharedState =
                                        { currentSharedState
                                            | appDataBindings = letBindingResult.appBindings
                                            , helperFunctions = newHelpers
                                        }
                                in
                                { context
                                    | sharedState = updatedSharedState
                                    , fieldBindings = letBindingResult.fieldBinds
                                    , fieldBindingRanges = letBindingResult.bindingRanges
                                }

                            _ ->
                                context


{-| Check if a function node is a call to View.freeze.
-}
isViewFreezeCall : Node Expression -> Context -> Bool
isViewFreezeCall functionNode context =
    PersistentFieldTracking.isViewFreezeCall functionNode context.lookupTable


{-| Check if an expression is `app.data` (or `static.data`, etc. based on context.sharedState.appParamName)
-}
isAppDataAccess : Node Expression -> Context -> Bool
isAppDataAccess node context =
    PersistentFieldTracking.isAppDataAccess node context.sharedState.appParamName context.sharedState.appDataBindings


{-| Delegate to shared isRecordAccessFunction function.
-}
isRecordAccessFunction : Node Expression -> Bool
isRecordAccessFunction =
    PersistentFieldTracking.isRecordAccessFunction




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
        context.sharedState.appParamName
        context.sharedState.appDataBindings
        (\fn -> isViewFreezeCall fn context)


{-| Extract field name from pipe operator with accessor pattern on app.data.
-}
extractAppDataPipeAccessorField : String -> Node Expression -> Node Expression -> Context -> Maybe String
extractAppDataPipeAccessorField op leftExpr rightExpr context =
    PersistentFieldTracking.extractAppDataPipeAccessorField op leftExpr rightExpr context.sharedState.appParamName context.sharedState.appDataBindings


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


{-| Find the index (0-based) of the parameter that has the `App` type.

This is used for functions like `init` and `update` where the App parameter
is not the first parameter. For example:

    init : Maybe PageUrl -> Shared.Model -> App Data ActionData RouteParams -> ( Model, Effect Msg )

The App parameter is at index 2 (third parameter).

Returns Nothing if no App parameter is found.

-}
findAppParamIndex : Node TypeAnnotation -> Maybe Int
findAppParamIndex typeAnnotation =
    findAppParamIndexHelper 0 typeAnnotation


findAppParamIndexHelper : Int -> Node TypeAnnotation -> Maybe Int
findAppParamIndexHelper index node =
    case Node.value node of
        TypeAnnotation.FunctionTypeAnnotation left right ->
            -- Check if the left side is an App type
            if isAppTypeAnnotation left then
                Just index

            else
                -- Recurse to the next parameter
                findAppParamIndexHelper (index + 1) right

        _ ->
            -- Not a function type - check if it's an App type (last parameter or simple type)
            if isAppTypeAnnotation node then
                Just index

            else
                Nothing


{-| Check if a type annotation is an App type (App Data ActionData RouteParams).
-}
isAppTypeAnnotation : Node TypeAnnotation -> Bool
isAppTypeAnnotation node =
    case Node.value node of
        TypeAnnotation.Typed (Node _ ( moduleName, typeName )) _ ->
            (moduleName == [] && typeName == "App")
                || (moduleName == [ "RouteBuilder" ] && typeName == "App")

        _ ->
            False


{-| Find all ranges where "Data" appears as a type in a type annotation.

This is used to replace Data with Ephemeral in freeze-only helper annotations.
Returns the ranges of the "Data" type references (not the full Typed node).

-}
findDataTypeRanges : Node TypeAnnotation -> List Range
findDataTypeRanges =
    PersistentFieldTracking.extractDataTypeRanges


{-| Add a field access to clientUsedFields if we're in a CLIENT context.
Fields accessed in ephemeral contexts (freeze, head) are NOT tracked.

Also tracks per-function field accesses for non-conventional head function names.
If the head function is defined before RouteBuilder, we initially track its field
accesses as client-used. In finalEvaluation, we subtract these fields when we
discover the actual head function name.
-}
addFieldAccess : String -> Context -> Context
addFieldAccess fieldName context =
    if context.sharedState.inFreezeCall || context.sharedState.inHeadFunction then
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

            currentSharedState =
                context.sharedState

            updatedSharedState =
                { currentSharedState | clientUsedFields = Set.insert fieldName currentSharedState.clientUsedFields }
        in
        { context
            | sharedState = updatedSharedState
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

Uses shared analyzeHelperCallInClientContext from PersistentFieldTracking.

-}
checkAppDataPassedToHelper : Context -> Node Expression -> List (Node Expression) -> Context
checkAppDataPassedToHelper context functionNode args =
    let
        classification =
            PersistentFieldTracking.classifyAppDataArguments
                functionNode
                args
                context.sharedState.appParamName
                context.sharedState.appDataBindings
                (\fn -> isViewFreezeCall fn context)
                (\expr -> containsAppDataExpression expr context)
    in
    if context.sharedState.inFreezeCall || context.sharedState.inHeadFunction then
        -- In ephemeral context (freeze/head)
        -- Track local functions called with app.data for potential stubbing (client-specific)
        case classification.maybeFuncName of
            Just funcName ->
                if classification.hasDirectAppData || classification.hasWrappedAppData then
                    { context | helpersCalledInFreeze = Set.insert funcName context.helpersCalledInFreeze }

                else
                    context

            Nothing ->
                context

    else
        -- In client context - use shared analysis with inline lambda fallback
        applyHelperCallResult context (PersistentFieldTracking.analyzeHelperCallInClientContext functionNode classification)


{-| Check if app.data is passed to a function via pipe operator.

Handles `app.data |> fn` and `fn <| app.data` patterns.
Uses shared analyzePipedHelperCall from PersistentFieldTracking.

-}
checkAppDataPassedToHelperViaPipe : Context -> Node Expression -> Node Expression -> Context
checkAppDataPassedToHelperViaPipe context functionNode argNode =
    -- Check if the argument is app.data (or an alias)
    if not (isAppDataAccess argNode context) then
        context

    else if context.sharedState.inFreezeCall || context.sharedState.inHeadFunction then
        -- In ephemeral context (freeze/head)
        -- Track local functions called with app.data for potential stubbing
        case extractBaseFunctionName functionNode of
            Just funcName ->
                { context | helpersCalledInFreeze = Set.insert funcName context.helpersCalledInFreeze }

            Nothing ->
                context

    else
        -- In client context - use shared pipe analysis
        applyHelperCallResult context (PersistentFieldTracking.analyzePipedHelperCall functionNode)


{-| Apply a HelperCallResult to the context.

This interprets the shared analysis result and updates the context accordingly.
Both checkAppDataPassedToHelper and checkAppDataPassedToHelperViaPipe use this.

-}
applyHelperCallResult : Context -> PersistentFieldTracking.HelperCallResult -> Context
applyHelperCallResult context result =
    case result of
        PersistentFieldTracking.HelperCallKnown helperCall ->
            let
                currentSharedState =
                    context.sharedState

                updatedSharedState =
                    { currentSharedState | pendingHelperCalls = Just helperCall :: currentSharedState.pendingHelperCalls }
            in
            { context | sharedState = updatedSharedState }

        PersistentFieldTracking.HelperCallLambdaFields accessedFields ->
            Set.foldl addFieldAccess context accessedFields

        PersistentFieldTracking.HelperCallUntrackable ->
            let
                currentSharedState =
                    context.sharedState

                updatedSharedState =
                    { currentSharedState | pendingHelperCalls = Nothing :: currentSharedState.pendingHelperCalls }
            in
            { context | sharedState = updatedSharedState }

        PersistentFieldTracking.HelperCallNoAction ->
            context


{-| Extract the base function name from a function expression.
Handles both simple function references and partial applications.
-}
extractBaseFunctionName : Node Expression -> Maybe String
extractBaseFunctionName node =
    case Node.value node of
        Expression.FunctionOrValue [] funcName ->
            Just funcName

        Expression.Application (firstExpr :: _) ->
            case Node.value firstExpr of
                Expression.FunctionOrValue [] funcName ->
                    Just funcName

                _ ->
                    Nothing

        Expression.ParenthesizedExpression inner ->
            extractBaseFunctionName inner

        _ ->
            Nothing


handleViewFreezeCall : Node Expression -> Node Expression -> Context -> ( List (Error {}), Context )
handleViewFreezeCall functionNode node context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "freeze" ->
            -- First check: are we inside a tainted conditional (if/case that depends on model)?
            -- If so, skip transformation to avoid server/client mismatch
            if context.taintedContextDepth > 0 then
                -- Inside tainted conditional - de-optimize (skip transformation)
                -- Emit count so build system can run validation pass
                ( [ emitDeOptimizationCount (Node.range node) "tainted_conditional" ], context )

            else
                -- Extract the freeze argument from the application
                case Node.value node of
                    Expression.Application (_ :: freezeArg :: []) ->
                        -- Check if the freeze argument is tainted (depends on model)
                        let
                            taintContext =
                                { modelParamName = context.modelParamName
                                , bindings = context.taintBindings
                                }

                            argTaint =
                                Taint.analyzeExpressionTaint taintContext freezeArg
                        in
                        case argTaint of
                            Taint.Tainted ->
                                -- Skip transformation - model is used, de-optimize gracefully
                                -- Emit count so build system can run validation pass
                                ( [ emitDeOptimizationCount (Node.range node) "tainted_argument" ], context )

                            Taint.Pure ->
                                -- Safe to transform - no model dependency
                                let
                                    -- Generate inlined lazy thunk with View.htmlToFreezable wrapper
                                    replacement =
                                        inlinedLazyThunk context

                                    fixes =
                                        [ Review.Fix.replaceRangeBy (Node.range node) replacement ]
                                            ++ htmlLazyImportFix context
                                in
                                ( [ createTransformErrorWithFixes "View.freeze" "inlined lazy thunk" node fixes ]
                                , { context | staticIndex = context.staticIndex + 1 }
                                )

                    _ ->
                        -- Unexpected structure, skip
                        ( [], context )

        _ ->
            ( [], context )


createTransformErrorWithFixes : String -> String -> Node Expression -> List Review.Fix.Fix -> Error {}
createTransformErrorWithFixes fromFn toFn node fixes =
    Rule.errorWithFix
        { message = "Frozen view codemod: transform " ++ fromFn ++ " to " ++ toFn
        , details = [ "Transforms " ++ fromFn ++ " to " ++ toFn ++ " for client-side adoption and DCE" ]
        }
        (Node.range node)
        fixes


{-| Generate fixes to add `import Html.Lazy` and `import VirtualDom` if not already imported.
The generated code uses:
- `Html.Lazy.lazy` for the lazy thunk
- `VirtualDom.text ""` as the placeholder (avoids conflicts with Html.Styled aliased as Html)
-}
htmlLazyImportFix : Context -> List Review.Fix.Fix
htmlLazyImportFix context =
    let
        needsHtmlLazy =
            case context.htmlLazyImport of
                ImportedAs _ ->
                    False

                NotImported ->
                    True

        needsVirtualDom =
            not context.virtualDomImported

        importsToAdd =
            (if needsHtmlLazy then
                "import Html.Lazy\n"

             else
                ""
            )
                ++ (if needsVirtualDom then
                        "import VirtualDom\n"

                    else
                        ""
                   )
    in
    if String.isEmpty importsToAdd then
        []

    else
        [ Review.Fix.insertAt
            { row = context.lastImportRow + 1, column = 1 }
            importsToAdd
        ]


{-| Generate inlined lazy thunk with View.htmlToFreezable wrapper and map never.

The generated code:

    Html.Lazy.lazy (\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0"
        |> View.htmlToFreezable
        |> Html.Styled.map never

This creates a lazy thunk with a magic string prefix that the virtual-dom codemod
detects at runtime to adopt pre-rendered HTML. The View.htmlToFreezable wrapper
converts the Html.Html Never back to the user's Freezable type, and map never converts
from `Freezable` (Html Never) to `Html msg`.

We use `VirtualDom.text ""` instead of `Html.text ""` because:
1. VirtualDom is always available (it's a dependency of elm/html)
2. VirtualDom.Node is the same type as Html.Html
3. It avoids conflicts when Html.Styled is aliased as "Html"

-}
inlinedLazyThunk : Context -> String
inlinedLazyThunk context =
    let
        htmlLazyPrefix =
            case context.htmlLazyImport of
                ImportedAs alias ->
                    String.join "." alias

                NotImported ->
                    "Html.Lazy"

        -- Determine the map function prefix based on whether Html.Styled is used
        -- If Html.Styled is imported, use it for map never; otherwise use plain Html
        mapPrefix =
            case context.htmlStyledAlias of
                Just alias ->
                    String.join "." alias

                Nothing ->
                    "Html"

        -- Magic prefix that vdom codemod detects
        -- Shared module uses "shared:" prefix to distinguish from Route frozen views
        staticId =
            let
                prefix =
                    if context.moduleName == [ "Shared" ] then
                        "shared:"

                    else
                        ""
            in
            "\"__ELM_PAGES_STATIC__" ++ prefix ++ String.fromInt context.staticIndex ++ "\""
    in
    -- Generate: Html.Lazy.lazy (\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.Styled.map never
    "(" ++ htmlLazyPrefix ++ ".lazy (\\_ -> VirtualDom.text \"\") " ++ staticId ++ " |> View.htmlToFreezable |> " ++ mapPrefix ++ ".map never)"


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
                        PersistentFieldTracking.extractFieldNames context.sharedState.dataTypeFields

                    -- Resolve pending helper calls against the now-complete helperFunctions dict
                    -- Returns (additionalClientUsedFields, shouldMarkAllFieldsAsClientUsed)
                    ( resolvedHelperFields, unresolvedHelperCalls ) =
                        PersistentFieldTracking.resolvePendingHelperCalls
                            context.sharedState.pendingHelperCalls
                            context.sharedState.helperFunctions

                    -- Combine direct field accesses with helper-resolved fields
                    combinedClientUsedFields =
                        Set.union context.sharedState.clientUsedFields resolvedHelperFields

                    -- Subtract fields accessed by the head function (for non-conventional naming)
                    -- When head = seoTags and seoTags is defined before RouteBuilder,
                    -- its field accesses were initially tracked as client-used. Now we correct that.
                    correctedClientUsedFields =
                        Set.diff combinedClientUsedFields headFunctionFields

                    -- Apply safe fallback: if we can't track field usage, mark ALL as client-used
                    effectiveClientUsedFields =
                        if context.sharedState.markAllFieldsAsUsed || unresolvedHelperCalls then
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
                        context.sharedState.dataTypeFields
                            |> List.filter (\( name, _ ) -> Set.member name effectiveClientUsedFields)
                    -- Track WHY all fields might be client-used (for diagnostics)
                    skipReason =
                        if context.sharedState.markAllFieldsAsUsed then
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
                            context.sharedState.pendingHelperCalls
                                |> List.filterMap identity
                                |> List.map .funcName
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
                                            ++ (context.sharedState.dataTypeFields
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


{-| Emit a de-optimization count message.
This signals to the build system that a View.freeze call was skipped
(not transformed) due to taint analysis. The build system can use this
to trigger a validation pass that provides user-friendly error messages.
-}
emitDeOptimizationCount : Range -> String -> Error {}
emitDeOptimizationCount range reason =
    Rule.error
        { message = "DEOPTIMIZATION_COUNT_JSON:{\"count\":1,\"reason\":\"" ++ reason ++ "\"}"
        , details = [ "View.freeze optimization skipped due to " ++ reason ]
        }
        range


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
