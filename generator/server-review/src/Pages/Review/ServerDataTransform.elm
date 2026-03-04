module Pages.Review.ServerDataTransform exposing (rule)

{-| This rule transforms Route modules for the server/CLI bundle.

It performs the following transformations:

1.  Renames `type alias Data = {...}` to `type alias Ephemeral = {...}`
2.  Creates new `type alias Data = {...}` with only persistent fields
3.  Generates `ephemeralToData : Ephemeral -> Data` conversion function

This enables the server to:

  - Render views using the full `Ephemeral` type (all fields available)
  - Encode only `Data` for wire transmission (reduced payload)
  - Use standard Wire3 encoders/decoders for `Data` on both server and client

-}

import Char
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
import Pages.Review.FreezeHelperPlanning as FreezeHelperPlanning
import Pages.Review.PersistentFieldTracking as PersistentFieldTracking
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


{-| Analysis of a helper function's field usage on its first parameter.
-}
type alias HelperAnalysis =
    PersistentFieldTracking.HelperAnalysis


type alias ProjectContext =
    { freezeFunctions : Dict ( ModuleName, String ) Int
    , functionCalls : Dict ( ModuleName, String ) (Set ( ModuleName, String ))
    , functionArities : Dict ( ModuleName, String ) Int
    , functionHasFidParam : Dict ( ModuleName, String ) Bool
    , helperFunctions : Dict String (List HelperAnalysis)
    }


initialProjectContext : ProjectContext
initialProjectContext =
    { freezeFunctions = Dict.empty
    , functionCalls = Dict.empty
    , functionArities = Dict.empty
    , functionHasFidParam = Dict.empty
    , helperFunctions = Dict.empty
    }


type alias FunctionDeclarationInfo =
    { functionNameRange : Range
    , firstArgRange : Maybe Range
    , signatureTypeRange : Maybe Range
    , argumentCount : Int
    , fidParamName : Maybe String
    , hasFidParam : Bool
    , hasFidTypeAnnotation : Bool
    }


type alias DeferredHelperCall =
    { callRange : Range
    , functionRange : Range
    , firstArgRange : Maybe Range
    , callerFunctionName : String
    , calleeFunctionId : ( ModuleName, String )
    }


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , moduleName : ModuleName
    , projectFreezeFunctions : Dict ( ModuleName, String ) Int
    , projectFunctionCalls : Dict ( ModuleName, String ) (Set ( ModuleName, String ))
    , projectFunctionArities : Dict ( ModuleName, String ) Int
    , projectFunctionHasFidParam : Dict ( ModuleName, String ) Bool
    , staticIndex : Int
    , helperCallSeedIndex : Int
    , functionDeclarationInfo : Dict String FunctionDeclarationInfo
    , injectedFidFunctions : Set String
    , helperFunctionFreezeIndex : Dict String Int
    , localTransformedFreezeFunctions : Dict String Int
    , localFunctionCalls : Dict ( ModuleName, String ) (Set ( ModuleName, String ))

    -- Shared field tracking state (embedded from PersistentFieldTracking)
    -- This contains: clientUsedFields, freezeCallDepth, inHeadFunction, appDataBindings,
    -- appParamName, helperFunctions, pendingHelperCalls, dataTypeFields, markAllFieldsAsUsed
    , sharedState : PersistentFieldTracking.SharedFieldTrackingState

    -- Track where Data is used as a record constructor (needs to become Ephemeral)
    , dataConstructorRanges : List Range

    -- Data type location
    , dataTypeRange : Maybe Range

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

    -- Import aliases for Html and Html.Attributes (for freeze wrapping)
    , htmlAlias : Maybe ModuleName
    , htmlAttributesAlias : Maybe ModuleName

    -- Track last import row for inserting new imports
    , lastImportRow : Int

    -- Lambda depth: when > 0 we are inside a repeated-execution context where
    -- helper ID seeding is not guaranteed to be unique per invocation.
    , lambdaDepth : Int

    -- Stack of let-bound local functions that directly call helpers requiring frozen ID seeding.
    -- Used to flag unsupported function-value/partial usage like `List.map renderItem`.
    , localLetFunctionsNeedingSeed : List (Set String)
    , deferredHelperCalls : List DeferredHelperCall
    }


rule : Rule
rule =
    Rule.newProjectRuleSchema "Pages.Review.ServerDataTransform" initialProjectContext
        |> Rule.withContextFromImportedModules
        |> Rule.withModuleVisitor moduleVisitor
        |> Rule.withModuleContextUsingContextCreator
            { fromProjectToModule = fromProjectToModule
            , fromModuleToProject = fromModuleToProject
            , foldProjectContexts = foldProjectContexts
            }
        |> Rule.fromProjectRuleSchema


moduleVisitor :
    Rule.ModuleRuleSchema {} Context
    -> Rule.ModuleRuleSchema { hasAtLeastOneVisitor : () } Context
moduleVisitor schema =
    schema
        |> Rule.providesFixesForModuleRule
        |> Rule.withImportVisitor importVisitor
        |> Rule.withModuleDefinitionVisitor moduleDefinitionVisitor
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withDeclarationExitVisitor declarationExitVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation


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


fromProjectToModule : Rule.ContextCreator ProjectContext Context
fromProjectToModule =
    Rule.initContextCreator
        (\lookupTable moduleName projectContext ->
            { lookupTable = lookupTable
            , moduleName = moduleName
            , projectFreezeFunctions = projectContext.freezeFunctions
            , projectFunctionCalls = projectContext.functionCalls
            , projectFunctionArities = projectContext.functionArities
            , projectFunctionHasFidParam = projectContext.functionHasFidParam
            , staticIndex = 0
            , helperCallSeedIndex = 0
            , functionDeclarationInfo = Dict.empty
            , injectedFidFunctions = Set.empty
            , helperFunctionFreezeIndex = Dict.empty
            , localTransformedFreezeFunctions = Dict.empty
            , localFunctionCalls = Dict.empty
            , sharedState =
                PersistentFieldTracking.emptySharedState
                    |> (\sharedState -> { sharedState | helperFunctions = projectContext.helperFunctions })
            , dataConstructorRanges = []
            , dataTypeRange = Nothing
            , dataTypeEndRow = 0
            , dataFunctionSignatureRange = Nothing
            , dataFunctionSignature = Nothing
            , hasEphemeralType = False
            , dataTypeReferenceRanges = []
            , dataExportRange = Nothing
            , htmlAlias = Nothing
            , htmlAttributesAlias = Nothing
            , lastImportRow = 0
            , lambdaDepth = 0
            , localLetFunctionsNeedingSeed = []
            , deferredHelperCalls = []
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


fromModuleToProject : Rule.ContextCreator Context ProjectContext
fromModuleToProject =
    Rule.initContextCreator
        (\moduleName context ->
            { freezeFunctions =
                Dict.foldl
                    (\fnName count acc ->
                        if count > 0 then
                            Dict.insert ( moduleName, fnName ) count acc

                        else
                            acc
                    )
                    Dict.empty
                    context.localTransformedFreezeFunctions
            , functionCalls = context.localFunctionCalls
            , functionArities =
                Dict.foldl
                    (\functionName info acc ->
                        Dict.insert ( moduleName, functionName ) info.argumentCount acc
                    )
                    Dict.empty
                    context.functionDeclarationInfo
            , functionHasFidParam =
                Dict.foldl
                    (\functionName info acc ->
                        Dict.insert ( moduleName, functionName ) info.hasFidParam acc
                    )
                    Dict.empty
                    context.functionDeclarationInfo
            , helperFunctions =
                Dict.filter
                    (\helperKey _ ->
                        case PersistentFieldTracking.helperKeyToFunctionId helperKey of
                            Just ( helperModuleName, _ ) ->
                                helperModuleName == moduleName

                            Nothing ->
                                False
                    )
                    context.sharedState.helperFunctions
            }
        )
        |> Rule.withModuleName


foldProjectContexts : ProjectContext -> ProjectContext -> ProjectContext
foldProjectContexts a b =
    let
        mergedFunctionCalls =
            Dict.foldl
                (\caller callees acc ->
                    Dict.update caller
                        (\maybeExisting ->
                            Just <|
                                case maybeExisting of
                                    Just existing ->
                                        Set.union existing callees

                                    Nothing ->
                                        callees
                        )
                        acc
                )
                a.functionCalls
                b.functionCalls

        mergedDirectFreezeFunctions =
            Dict.union a.freezeFunctions b.freezeFunctions

        mergedFunctionArities =
            Dict.union a.functionArities b.functionArities

        mergedFunctionHasFidParam =
            Dict.union a.functionHasFidParam b.functionHasFidParam

        mergedHelperFunctions =
            Dict.union a.helperFunctions b.helperFunctions
    in
    { freezeFunctions = FreezeHelperPlanning.computeTransitiveFreezeFunctions mergedDirectFreezeFunctions mergedFunctionCalls
    , functionCalls = mergedFunctionCalls
    , functionArities = mergedFunctionArities
    , functionHasFidParam = mergedFunctionHasFidParam
    , helperFunctions = mergedHelperFunctions
    }


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
                functionDeclaration =
                    Node.value function.declaration

                functionName =
                    functionDeclaration.name
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

                functionInfo =
                    let
                        maybeExistingFidParamName =
                            functionDeclaration.arguments
                                |> List.head
                                |> Maybe.andThen fidParamNameFromPattern
                    in
                    { functionNameRange = Node.range functionDeclaration.name
                    , firstArgRange = List.head functionDeclaration.arguments |> Maybe.map Node.range
                    , signatureTypeRange = function.signature |> Maybe.map (\signatureNode -> Node.range (Node.value signatureNode).typeAnnotation)
                    , argumentCount = List.length functionDeclaration.arguments
                    , fidParamName = maybeExistingFidParamName
                    , hasFidParam = maybeExistingFidParamName /= Nothing
                    , hasFidTypeAnnotation =
                        case function.signature of
                            Just signatureNode ->
                                signatureStartsWithString (Node.value signatureNode).typeAnnotation

                            Nothing ->
                                False
                    }

                contextWithFunctionInfo =
                    { contextWithDataRefs
                        | functionDeclarationInfo =
                            Dict.insert functionName functionInfo contextWithDataRefs.functionDeclarationInfo
                    }

                -- Track current function for per-function field tracking
                -- This enables correction for non-conventional head function naming
                contextWithFunctionEnter =
                    { contextWithFunctionInfo
                        | sharedState = PersistentFieldTracking.updateOnFunctionEnter functionName contextWithFunctionInfo.sharedState
                    }

                -- Determine the actual head function name from RouteBuilder
                -- Uses shared state to ensure agreement with StaticViewTransform
                actualHeadFn =
                    contextWithFunctionEnter.sharedState.routeBuilderHeadFn
                        |> Maybe.withDefault "head"
            in
            if functionName == actualHeadFn then
                ( [], { contextWithFunctionEnter | sharedState = PersistentFieldTracking.updateOnHeadEnter contextWithFunctionEnter.sharedState } )

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
                        , { contextWithFunctionEnter
                            | dataFunctionSignatureRange = Just (Node.range typeAnnotation)
                            , dataFunctionSignature = Just signatureStr
                          }
                        )

                    Nothing ->
                        ( [], contextWithFunctionEnter )

            else if functionName == "view" || functionName == "init" || functionName == "update" then
                -- Extract the App parameter name from client-side functions
                -- The first parameter is typically named "app" or "static"
                -- We need to track field usage in ALL client-side functions, not just view
                -- because fields accessed in init/update also need to be in the client Data type
                --
                -- IMPORTANT: We always update appParamName for each client function because
                -- different functions might use different parameter names (e.g., init might
                -- use "shared" while view uses "app" due to unconventional naming).
                -- Since field tracking happens INSIDE each function, we need the correct
                -- param name for each function at the time we're visiting it.
                let
                    arguments =
                        function.declaration
                            |> Node.value
                            |> .arguments

                    maybeAppParamPattern =
                        arguments
                            |> List.head

                    maybeAppParam =
                        maybeAppParamPattern
                            |> Maybe.andThen PersistentFieldTracking.extractPatternName

                    -- Extract app.data bindings from patterns like ({ data } as app)
                    appDataBindingsFromPattern =
                        maybeAppParamPattern
                            |> Maybe.map PersistentFieldTracking.extractAppDataBindingsFromPattern
                            |> Maybe.withDefault Set.empty

                    currentSharedState =
                        contextWithFunctionEnter.sharedState

                    updatedSharedState =
                        { currentSharedState
                            | appParamName = maybeAppParam
                            , appDataBindings = Set.union currentSharedState.appDataBindings appDataBindingsFromPattern
                        }
                in
                ( [], { contextWithFunctionEnter | sharedState = updatedSharedState } )

            else
                -- Analyze non-special functions as potential helpers
                -- This allows us to track which fields they access when called with app.data
                let
                    helperAnalysis =
                        PersistentFieldTracking.analyzeHelperFunction function

                    contextWithHelper =
                        if List.isEmpty helperAnalysis then
                            contextWithFunctionEnter

                        else
                            let
                                currentSharedState =
                                    contextWithFunctionEnter.sharedState

                                updatedSharedState =
                                    { currentSharedState
                                        | helperFunctions =
                                            Dict.insert
                                                (PersistentFieldTracking.functionIdToHelperKey ( context.moduleName, functionName ))
                                                helperAnalysis
                                                currentSharedState.helperFunctions
                                    }
                            in
                            { contextWithFunctionEnter | sharedState = updatedSharedState }
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
                                PersistentFieldTracking.extractDataTypeFields recordFields

                            endRow =
                                (Node.range node).end.row

                            currentSharedState =
                                context.sharedState

                            updatedSharedState =
                                { currentSharedState | dataTypeFields = fields }
                        in
                        ( []
                        , { context
                            | dataTypeRange = Just (Node.range node)
                            , sharedState = updatedSharedState
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

                -- Always call updateOnFunctionExit for all functions
                contextWithFunctionExit =
                    { context | sharedState = PersistentFieldTracking.updateOnFunctionExit context.sharedState }

                -- Determine the actual head function name from RouteBuilder
                -- Uses shared state to ensure agreement with StaticViewTransform
                actualHeadFn =
                    context.sharedState.routeBuilderHeadFn
                        |> Maybe.withDefault "head"
            in
            if functionName == actualHeadFn then
                ( [], { contextWithFunctionExit | sharedState = PersistentFieldTracking.updateOnHeadExit contextWithFunctionExit.sharedState } )

            else
                ( [], contextWithFunctionExit )

        _ ->
            ( [], context )


type alias FreezeCall =
    { functionNode : Node Expression
    , args : List (Node Expression)
    }


{-| Extract a View.freeze call from supported call shapes.

Supports:
- `View.freeze expr`
- `expr |> View.freeze`
- `View.freeze <| expr`

-}
extractFreezeCall : Node Expression -> Context -> Maybe FreezeCall
extractFreezeCall node context =
    let
        check functionNode args =
            let
                unwrappedFunction =
                    unwrapParenthesizedExpression functionNode
            in
            case args of
                [ _ ] ->
                    if isViewFreezeCall unwrappedFunction context then
                        Just { functionNode = unwrappedFunction, args = args }

                    else
                        Nothing

                _ ->
                    Nothing
    in
    case Node.value node of
        Expression.Application (functionNode :: args) ->
            check functionNode args

        Expression.OperatorApplication "|>" _ leftExpr rightExpr ->
            check rightExpr [ leftExpr ]

        Expression.OperatorApplication "<|" _ leftExpr rightExpr ->
            check leftExpr [ rightExpr ]

        _ ->
            Nothing


recordFunctionCallEdge : Node Expression -> Context -> Context
recordFunctionCallEdge functionNode context =
    case ( currentFunctionName context, resolveCalledFunctionId functionNode context ) of
        ( Just callerFunctionName, Just calleeFunctionId ) ->
            let
                callerFunctionId =
                    ( context.moduleName, callerFunctionName )
            in
            { context
                | localFunctionCalls =
                    Dict.update callerFunctionId
                        (\maybeExisting ->
                            Just <|
                                case maybeExisting of
                                    Just existing ->
                                        Set.insert calleeFunctionId existing

                                    Nothing ->
                                        Set.singleton calleeFunctionId
                        )
                        context.localFunctionCalls
            }

        _ ->
            context


resolveCalledFunctionId : Node Expression -> Context -> Maybe ( ModuleName, String )
resolveCalledFunctionId functionNode context =
    let
        unwrapped =
            unwrapParenthesizedExpression functionNode
    in
    case Node.value unwrapped of
        Expression.FunctionOrValue qualifier fnName ->
            case ModuleNameLookupTable.moduleNameFor context.lookupTable unwrapped of
                Just moduleName ->
                    if List.isEmpty moduleName then
                        Just ( context.moduleName, fnName )

                    else
                        Just ( moduleName, fnName )

                Nothing ->
                    if List.isEmpty qualifier then
                        Just ( context.moduleName, fnName )

                    else
                        Just ( qualifier, fnName )

        _ ->
            Nothing


rewriteHelperCallWithFrozenId : Node Expression -> Context -> ( List (Error {}), Context )
rewriteHelperCallWithFrozenId node context =
    case Node.value node of
        Expression.Application (functionNode :: args) ->
            if shouldSeedHelperCallIds context then
                case findUnsupportedHelperFunctionValueOrPartialArg args context of
                    Just unsupportedArg ->
                        ( [ unsupportedHelperFunctionValueOrPartialError "Server codemod: unsupported helper function value or partial application" unsupportedArg ]
                        , context
                        )

                    Nothing ->
                        if helperCallNeedsFrozenId functionNode context then
                            let
                                contextWithFreezePresence =
                                    recordTransformedFreezeInCurrentFunction context
                            in
                            if isPartialHelperCall functionNode args contextWithFreezePresence then
                                ( [ unsupportedHelperFunctionValueOrPartialError "Server codemod: unsupported helper function value or partial application" node ]
                                , contextWithFreezePresence
                                )

                            else if currentFunctionIsRecursive contextWithFreezePresence then
                                ( [ Rule.error
                                        { message = "Server codemod: unsupported helper ID seeding in repeated context"
                                        , details =
                                            [ "Cannot auto-seed frozen helper IDs inside recursive helper functions."
                                            , "Refactor recursion so each invocation receives an explicit unique frozen ID seed."
                                            ]
                                        }
                                        (Node.range node)
                                  ]
                                , contextWithFreezePresence
                                )

                            else if contextWithFreezePresence.lambdaDepth > 0 then
                                ( [ Rule.error
                                        { message = "Server codemod: unsupported helper ID seeding in repeated context"
                                        , details =
                                            [ "Cannot auto-seed frozen helper IDs inside lambdas or higher-order iterations (for example List.map)."
                                            , "Refactor this helper call to a static call site so each invocation can get a unique frozen ID."
                                            ]
                                        }
                                        (Node.range node)
                                  ]
                                , contextWithFreezePresence
                                )

                            else if callAlreadyHasFrozenIdSeed args then
                                ( [], contextWithFreezePresence )

                            else
                                let
                                    ( frozenSeedExpression, contextWithSeed ) =
                                        nextHelperCallSeedExpression contextWithFreezePresence

                                    insertionFix =
                                        case args of
                                            firstArg :: _ ->
                                                Review.Fix.insertAt (Node.range firstArg).start (frozenSeedExpression ++ " ")

                                            [] ->
                                                Review.Fix.insertAt (Node.range functionNode).end (" " ++ frozenSeedExpression)

                                    helperDeclarationFixes =
                                        helperFidInjectionFixes contextWithSeed
                                in
                                ( [ Rule.errorWithFix
                                        { message = "Server codemod: pass frozen ID to helper call"
                                        , details = [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze." ]
                                        }
                                        (Node.range node)
                                        (insertionFix :: helperDeclarationFixes)
                                  ]
                                , markCurrentFunctionFidInjected contextWithSeed
                                )

                        else
                            case recordDeferredLocalHelperCall node functionNode args context of
                                Just deferredContext ->
                                    ( [], deferredContext )

                                Nothing ->
                                    ( [], context )

            else
                ( [], context )

        _ ->
            ( [], context )


recordDeferredLocalHelperCall : Node Expression -> Node Expression -> List (Node Expression) -> Context -> Maybe Context
recordDeferredLocalHelperCall node functionNode args context =
    case ( currentFunctionName context, resolveCalledFunctionId functionNode context ) of
        ( Just callerFunctionName, Just calleeFunctionId ) ->
            let
                ( calleeModuleName, calleeFunctionName ) =
                    calleeFunctionId
            in
            if calleeModuleName /= context.moduleName then
                Nothing

            else if Dict.member calleeFunctionName context.functionDeclarationInfo then
                Nothing

            else if callAlreadyHasFrozenIdSeed args then
                Nothing

            else
                Just
                    { context
                        | deferredHelperCalls =
                            { callRange = Node.range node
                            , functionRange = Node.range functionNode
                            , firstArgRange = List.head args |> Maybe.map Node.range
                            , callerFunctionName = callerFunctionName
                            , calleeFunctionId = calleeFunctionId
                            }
                                :: context.deferredHelperCalls
                    }

        _ ->
            Nothing


shouldSeedHelperCallIds : Context -> Bool
shouldSeedHelperCallIds context =
    FreezeHelperPlanning.shouldSeedHelperCallIds
        { isRouteModule = PersistentFieldTracking.isRouteModule
        , isSharedModule = PersistentFieldTracking.isSharedModule
        , moduleName = context.moduleName
        , currentFunctionName = currentFunctionName context
        
        }


helperCallNeedsFrozenId : Node Expression -> Context -> Bool
helperCallNeedsFrozenId functionNode context =
    FreezeHelperPlanning.helperCallNeedsFrozenId
        (freezeKnowledge context)
        (\calledFunctionNode -> resolveCalledFunctionId calledFunctionNode context)
        functionNode


findUnsupportedHelperFunctionValueOrPartialArg : List (Node Expression) -> Context -> Maybe (Node Expression)
findUnsupportedHelperFunctionValueOrPartialArg args context =
    case
        FreezeHelperPlanning.findUnsupportedHelperFunctionValueArg
            (freezeKnowledge context)
            (\calledFunctionNode -> resolveCalledFunctionId calledFunctionNode context)
            args
    of
        Just unsupportedArg ->
            Just unsupportedArg

        Nothing ->
            FreezeHelperPlanning.findUnsupportedLocalFunctionValueArg
                (currentLocalLetFunctionsNeedingSeed context)
                args


isPartialHelperCall : Node Expression -> List (Node Expression) -> Context -> Bool
isPartialHelperCall functionNode args context =
    FreezeHelperPlanning.isPartialHelperCall
        (freezeKnowledge context)
        (\calledFunctionNode -> resolveCalledFunctionId calledFunctionNode context)
        functionNode
        args


unsupportedHelperFunctionValueOrPartialError : String -> Node Expression -> Error {}
unsupportedHelperFunctionValueOrPartialError message expressionNode =
    Rule.error
        { message = message
        , details =
            [ "Cannot pass a helper containing View.freeze as a function value or partial application (for example List.map Helper.view)."
            , "Refactor this helper call to a static call site so each invocation can get a unique frozen ID."
            ]
        }
        (Node.range expressionNode)


freezeKnowledge : Context -> FreezeHelperPlanning.FreezeKnowledge
freezeKnowledge context =
    let
        localFreezeFunctions =
            Dict.foldl
                (\fnName count acc ->
                    if count > 0 then
                        Dict.insert ( context.moduleName, fnName ) count acc

                    else
                        acc
                )
                Dict.empty
                context.localTransformedFreezeFunctions

        mergedFunctionCalls =
            Dict.foldl
                (\caller callees acc ->
                    Dict.update caller
                        (\maybeExisting ->
                            Just <|
                                case maybeExisting of
                                    Just existing ->
                                        Set.union existing callees

                                    Nothing ->
                                        callees
                        )
                        acc
                )
                context.projectFunctionCalls
                context.localFunctionCalls

        localFunctionArities =
            Dict.foldl
                (\functionName info acc ->
                    Dict.insert ( context.moduleName, functionName ) info.argumentCount acc
                )
                Dict.empty
                context.functionDeclarationInfo

        localFunctionHasFidParam =
            Dict.foldl
                (\functionName info acc ->
                    Dict.insert ( context.moduleName, functionName ) info.hasFidParam acc
                )
                Dict.empty
                context.functionDeclarationInfo
    in
    { freezeFunctions = Dict.union localFreezeFunctions context.projectFreezeFunctions
    , functionCalls = mergedFunctionCalls
    , functionArities = Dict.union localFunctionArities context.projectFunctionArities
    , functionHasFidParam = Dict.union localFunctionHasFidParam context.projectFunctionHasFidParam
    }


currentLocalLetFunctionsNeedingSeed : Context -> Set String
currentLocalLetFunctionsNeedingSeed context =
    context.localLetFunctionsNeedingSeed
        |> List.foldl Set.union Set.empty


currentFunctionIsRecursive : Context -> Bool
currentFunctionIsRecursive context =
    case currentFunctionName context of
        Just functionName ->
            FreezeHelperPlanning.functionIsRecursive
                (freezeKnowledge context)
                ( context.moduleName, functionName )

        Nothing ->
            False


callAlreadyHasFrozenIdSeed : List (Node Expression) -> Bool
callAlreadyHasFrozenIdSeed args =
    case args of
        firstArg :: _ ->
            case Node.value (unwrapParenthesizedExpression firstArg) of
                Expression.Literal _ ->
                    True

                _ ->
                    expressionContainsFidVariable firstArg

        [] ->
            False


expressionContainsFidVariable : Node Expression -> Bool
expressionContainsFidVariable node =
    case Node.value (unwrapParenthesizedExpression node) of
        Expression.FunctionOrValue [] fnName ->
            isFidParamName fnName

        Expression.OperatorApplication _ _ left right ->
            expressionContainsFidVariable left || expressionContainsFidVariable right

        Expression.Application exprs ->
            List.any expressionContainsFidVariable exprs

        Expression.IfBlock condition thenBranch elseBranch ->
            expressionContainsFidVariable condition
                || expressionContainsFidVariable thenBranch
                || expressionContainsFidVariable elseBranch

        Expression.CaseExpression caseBlock ->
            expressionContainsFidVariable caseBlock.expression

        Expression.ParenthesizedExpression inner ->
            expressionContainsFidVariable inner

        _ ->
            False


nextHelperCallSeedExpression : Context -> ( String, Context )
nextHelperCallSeedExpression context =
    let
        nextContext =
            { context | helperCallSeedIndex = context.helperCallSeedIndex + 1 }
    in
    if usesHelperFrozenIds context then
        ( "(" ++ currentFunctionFidParamName context ++ " ++ \":" ++ String.fromInt context.helperCallSeedIndex ++ "\")"
        , nextContext
        )

    else
        ( "\"" ++ nextHelperCallSeed context ++ "\""
        , nextContext
        )


nextHelperCallSeed : Context -> String
nextHelperCallSeed context =
    let
        prefix =
            if context.moduleName == [ "Shared" ] then
                "shared:"

            else
                ""
    in
    prefix ++ String.fromInt context.helperCallSeedIndex


advanceRootSeedIndex : Context -> Context
advanceRootSeedIndex context =
    if shouldSeedHelperCallIds context then
        { context | staticIndex = context.staticIndex + 1 }

    else
        context


expressionEnterVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionEnterVisitor node context =
    let
        contextWithLambdaDepth =
            case Node.value node of
                Expression.LambdaExpression _ ->
                    { context | lambdaDepth = context.lambdaDepth + 1 }

                _ ->
                    context

        -- Track where Data is used as a record constructor (needs to become Ephemeral)
        contextWithDataConstructorCheck =
            case Node.value node of
                Expression.FunctionOrValue [] "Data" ->
                    { contextWithLambdaDepth | dataConstructorRanges = Node.range node :: contextWithLambdaDepth.dataConstructorRanges }

                _ ->
                    contextWithLambdaDepth

        -- Detect RouteBuilder calls and extract function names
        -- This ensures we correctly identify which functions are ephemeral (head, data)
        -- based on what's ACTUALLY passed to RouteBuilder, not just by function name
        -- Uses shared detection logic from PersistentFieldTracking
        contextWithRouteBuilder =
            case PersistentFieldTracking.isRouteBuilderCall contextWithDataConstructorCheck.lookupTable node of
                Just args ->
                    extractRouteBuilderHeadFn contextWithDataConstructorCheck args

                Nothing ->
                    contextWithDataConstructorCheck

        contextWithCallGraph =
            case Node.value node of
                Expression.Application (functionNode :: _) ->
                    recordFunctionCallEdge functionNode contextWithRouteBuilder

                Expression.OperatorApplication op _ leftExpr rightExpr ->
                    case op of
                        "|>" ->
                            recordFunctionCallEdge rightExpr contextWithRouteBuilder

                        "<|" ->
                            recordFunctionCallEdge leftExpr contextWithRouteBuilder

                        _ ->
                            contextWithRouteBuilder

                _ ->
                    contextWithRouteBuilder

        -- Track entering freeze calls, check for app.data passed in client context,
        -- and handle freeze wrapping
        ( freezeErrors, contextWithFreezeTracking ) =
            case extractFreezeCall node contextWithCallGraph of
                Just freezeCall ->
                    -- Handle View.freeze call - wrap argument if not already wrapped
                    let
                        contextWithFreezePresence =
                            recordTransformedFreezeInCurrentFunction contextWithCallGraph

                        ( errors, newContext ) =
                            handleViewFreezeWrapping node freezeCall.functionNode freezeCall.args contextWithFreezePresence
                    in
                    ( errors
                    , { newContext | sharedState = PersistentFieldTracking.updateOnFreezeEnter newContext.sharedState }
                    )

                Nothing ->
                    case Node.value node of
                        Expression.Application (functionNode :: args) ->
                            -- Check for app.data passed as whole in CLIENT context
                            ( [], checkAppDataPassedToHelper contextWithCallGraph functionNode args )

                        -- Handle pipe operators: app.data |> fn or fn <| app.data
                        -- But NOT accessor patterns like app.data |> .field (handled by trackFieldAccess)
                        Expression.OperatorApplication op _ leftExpr rightExpr ->
                            case op of
                                "|>" ->
                                    -- app.data |> fn  =>  fn(app.data), so fn is on the right
                                    -- Skip if fn is a RecordAccessFunction (.field) - handled elsewhere
                                    if isRecordAccessFunction rightExpr then
                                        ( [], contextWithCallGraph )

                                    else
                                        ( [], checkAppDataPassedToHelperViaPipe contextWithCallGraph rightExpr leftExpr )

                                "<|" ->
                                    -- fn <| app.data  =>  fn(app.data), so fn is on the left
                                    -- Skip if fn is a RecordAccessFunction (.field) - handled elsewhere
                                    if isRecordAccessFunction leftExpr then
                                        ( [], contextWithCallGraph )

                                    else
                                        ( [], checkAppDataPassedToHelperViaPipe contextWithCallGraph leftExpr rightExpr )

                                _ ->
                                    ( [], contextWithCallGraph )

                        _ ->
                            ( [], contextWithCallGraph )

        -- Track field access patterns
        contextWithFieldTracking =
            trackFieldAccess node contextWithFreezeTracking

        contextWithLocalLetFunctions =
            case Node.value node of
                Expression.LetExpression letBlock ->
                    let
                        localFunctionsNeedingSeed =
                            FreezeHelperPlanning.letFunctionsWithDirectSeededHelperCalls
                                (\functionNode -> helperCallNeedsFrozenId functionNode contextWithFieldTracking)
                                letBlock.declarations
                    in
                    { contextWithFieldTracking
                        | localLetFunctionsNeedingSeed =
                            localFunctionsNeedingSeed :: contextWithFieldTracking.localLetFunctionsNeedingSeed
                    }

                _ ->
                    contextWithFieldTracking

        ( helperCallErrors, contextWithHelperCalls ) =
            rewriteHelperCallWithFrozenId node contextWithLocalLetFunctions
    in
    ( freezeErrors ++ helperCallErrors, contextWithHelperCalls )


{-| Handle View.freeze calls - wrap the argument with data-static if not already wrapped.
Nested freeze calls are a no-op - only the outermost freeze gets transformed.
-}
handleViewFreezeWrapping : Node Expression -> Node Expression -> List (Node Expression) -> Context -> ( List (Error {}), Context )
handleViewFreezeWrapping applicationNode functionNode args context =
    -- Check if we're inside a nested freeze call
    -- Nested freeze should be a no-op - only transform the outermost freeze
    if context.sharedState.freezeCallDepth > 0 then
        -- Inside nested freeze - skip transformation (no-op)
        ( [], context )

    else
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
                    ( [], advanceRootSeedIndex context )

                else
                    -- Generate the wrapping fix
                    let
                        ( dataStaticIdExpression, contextWithIdProgress ) =
                            nextDataStaticIdExpression context

                        helperDeclarationFixes =
                            helperFidInjectionFixes contextWithIdProgress

                        -- Use ElmPages__ prefix when we're adding the import to avoid conflicts
                        -- with user imports (e.g., `import Accessibility as Html`)
                        htmlPrefix =
                            context.htmlAlias
                                |> Maybe.map (String.join ".")
                                |> Maybe.withDefault "ElmPages__Html"

                        attrPrefix =
                            context.htmlAttributesAlias
                                |> Maybe.map (String.join ".")
                                |> Maybe.withDefault "Html.Attributes"

                        -- Check if we need to add imports
                        needsHtmlImport =
                            context.htmlAlias == Nothing

                        needsHtmlAttributesImport =
                            context.htmlAttributesAlias == Nothing

                        -- Build import string with unique ElmPages__ prefix to avoid conflicts
                        -- with user imports (e.g., `import Accessibility as Html`)
                        importsToAdd =
                            (if needsHtmlImport then
                                "import Html as ElmPages__Html\n"

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

                        -- We'll wrap it with: View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml <arg> ])
                        -- This handles type conversion for elm-css and other view libraries where Freezable != Html.Html Never
                        -- Shared module uses "shared:" prefix to distinguish from Route frozen views
                        -- Need to add outer parentheses if not already parenthesized
                        ( wrapperPrefix, wrapperSuffix ) =
                            if isParenthesized then
                                -- Original had parentheses, we use the inner range and add just the wrapper
                                ( "View.htmlToFreezable ("
                                    ++ htmlPrefix
                                    ++ ".div [ "
                                    ++ attrPrefix
                                    ++ ".attribute \"data-static\" "
                                    ++ dataStaticIdExpression
                                    ++ " ] [ View.freezableToHtml ("
                                , ") ])"
                                )

                            else
                                -- Original didn't have parentheses, we need to add them
                                ( "(View.htmlToFreezable ("
                                    ++ htmlPrefix
                                    ++ ".div [ "
                                    ++ attrPrefix
                                    ++ ".attribute \"data-static\" "
                                    ++ dataStaticIdExpression
                                    ++ " ] [ View.freezableToHtml ("
                                , ") ]))"
                                )

                        wrapperFixes =
                            [ Review.Fix.insertAt innerRange.start wrapperPrefix
                            , Review.Fix.insertAt innerRange.end wrapperSuffix
                            ]

                        -- Combine import fixes with wrapper fixes
                        fix =
                            importFixes ++ helperDeclarationFixes ++ wrapperFixes
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
                    , markCurrentFunctionFidInjected contextWithIdProgress
                    )

            _ ->
                -- Not a single-argument application, ignore
                ( [], context )


frozenIdParamPrefix : String
frozenIdParamPrefix =
    "elmPagesFid"


currentFunctionName : Context -> Maybe String
currentFunctionName context =
    context.sharedState.currentFunctionName


isFidParamName : String -> Bool
isFidParamName name =
    String.startsWith frozenIdParamPrefix name


sanitizeFidNamePart : String -> String
sanitizeFidNamePart rawPart =
    rawPart
        |> String.toLower
        |> String.map
            (\char ->
                if Char.isAlphaNum char then
                    char

                else
                    '_'
            )


generatedFidParamName : ModuleName -> String -> String
generatedFidParamName moduleName functionName =
    let
        modulePart =
            moduleName
                |> List.map sanitizeFidNamePart
                |> String.join "_"

        functionPart =
            sanitizeFidNamePart functionName

        suffix =
            if String.isEmpty modulePart then
                functionPart

            else
                modulePart ++ "_" ++ functionPart
    in
    frozenIdParamPrefix ++ "_" ++ suffix


currentFunctionFidParamNameFor : Context -> String -> String
currentFunctionFidParamNameFor context functionName =
    case Dict.get functionName context.functionDeclarationInfo of
        Just info ->
            info.fidParamName
                |> Maybe.withDefault (generatedFidParamName context.moduleName functionName)

        Nothing ->
            generatedFidParamName context.moduleName functionName


currentFunctionFidParamName : Context -> String
currentFunctionFidParamName context =
    case currentFunctionName context of
        Just functionName ->
            currentFunctionFidParamNameFor context functionName

        Nothing ->
            frozenIdParamPrefix


usesHelperFrozenIdsForFunction : Context -> String -> Bool
usesHelperFrozenIdsForFunction context functionName =
    let
        hasExistingArguments =
            Dict.get functionName context.functionDeclarationInfo
                |> Maybe.map (\info -> info.argumentCount > 0)
                |> Maybe.withDefault True
    in
    hasExistingArguments
        && (if PersistentFieldTracking.isRouteModule context.moduleName || PersistentFieldTracking.isSharedModule context.moduleName then
                functionName /= "view"

            else
                True
           )


usesHelperFrozenIds : Context -> Bool
usesHelperFrozenIds context =
    case currentFunctionName context of
        Just functionName ->
            usesHelperFrozenIdsForFunction context functionName

        Nothing ->
            False


recordTransformedFreezeInCurrentFunction : Context -> Context
recordTransformedFreezeInCurrentFunction context =
    case currentFunctionName context of
        Just fnName ->
            { context
                | localTransformedFreezeFunctions =
                    Dict.update fnName
                        (\maybeCount ->
                            case maybeCount of
                                Just count ->
                                    Just (count + 1)

                                Nothing ->
                                    Just 1
                        )
                        context.localTransformedFreezeFunctions
            }

        Nothing ->
            context


nextDataStaticIdExpression : Context -> ( String, Context )
nextDataStaticIdExpression context =
    if usesHelperFrozenIds context then
        case currentFunctionName context of
            Just fnName ->
                let
                    localIndex =
                        Dict.get fnName context.helperFunctionFreezeIndex
                            |> Maybe.withDefault 0

                    updatedContext =
                        { context
                            | helperFunctionFreezeIndex =
                                Dict.insert fnName (localIndex + 1) context.helperFunctionFreezeIndex
                        }
                in
                ( "(" ++ currentFunctionFidParamName context ++ " ++ \":" ++ String.fromInt localIndex ++ "\")"
                , updatedContext
                )

            Nothing ->
                nextRootDataStaticIdExpression context

    else
        nextRootDataStaticIdExpression context


nextRootDataStaticIdExpression : Context -> ( String, Context )
nextRootDataStaticIdExpression context =
    let
        prefix =
            getStaticPrefix context.moduleName
    in
    ( "\"" ++ prefix ++ "__STATIC__\""
    , { context | staticIndex = context.staticIndex + 1 }
    )


helperFidInjectionFixes : Context -> List Review.Fix.Fix
helperFidInjectionFixes context =
    case currentFunctionName context of
        Just functionName ->
            if Set.member functionName context.injectedFidFunctions then
                []

            else
                helperFidInjectionFixesForFunction context functionName

        Nothing ->
            []


helperFidInjectionFixesForFunction : Context -> String -> List Review.Fix.Fix
helperFidInjectionFixesForFunction context functionName =
    if not (usesHelperFrozenIdsForFunction context functionName) then
        []

    else
        case Dict.get functionName context.functionDeclarationInfo of
            Nothing ->
                []

            Just info ->
                let
                    fidParamName =
                        generatedFidParamName context.moduleName functionName

                    declarationFixes =
                        if info.hasFidParam then
                            []

                        else
                            [ case info.firstArgRange of
                                Just firstArgRange ->
                                    Review.Fix.insertAt firstArgRange.start (fidParamName ++ " ")

                                Nothing ->
                                    Review.Fix.insertAt info.functionNameRange.end (" " ++ fidParamName)
                            ]

                    signatureFixes =
                        if info.hasFidTypeAnnotation then
                            []

                        else
                            case info.signatureTypeRange of
                                Just signatureTypeRange ->
                                    [ Review.Fix.insertAt signatureTypeRange.start "String -> " ]

                                Nothing ->
                                    []
                in
                declarationFixes ++ signatureFixes


markCurrentFunctionFidInjected : Context -> Context
markCurrentFunctionFidInjected context =
    case currentFunctionName context of
        Just functionName ->
            if usesHelperFrozenIdsForFunction context functionName then
                { context | injectedFidFunctions = Set.insert functionName context.injectedFidFunctions }

            else
                context

        Nothing ->
            context


fidParamNameFromPattern : Node Pattern -> Maybe String
fidParamNameFromPattern node =
    case Node.value node of
        Pattern.VarPattern name ->
            if isFidParamName name then
                Just name

            else
                Nothing

        Pattern.ParenthesizedPattern inner ->
            fidParamNameFromPattern inner

        Pattern.AsPattern inner (Node _ name) ->
            if isFidParamName name then
                Just name

            else
                fidParamNameFromPattern inner

        _ ->
            Nothing


signatureStartsWithString : Node TypeAnnotation -> Bool
signatureStartsWithString node =
    case Node.value node of
        TypeAnnotation.FunctionTypeAnnotation firstArg _ ->
            isStringTypeAnnotation firstArg

        _ ->
            False


isStringTypeAnnotation : Node TypeAnnotation -> Bool
isStringTypeAnnotation node =
    case Node.value node of
        TypeAnnotation.Typed (Node _ ( [], "String" )) [] ->
            True

        _ ->
            False


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

Looks for patterns:
1. View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "..." ] [ ... ])
2. Html.div [ Html.Attributes.attribute "data-static" "..." ] [ ... ] (legacy)

-}
isAlreadyWrappedWithDataStatic : Node Expression -> Bool
isAlreadyWrappedWithDataStatic node =
    case Node.value node of
        Expression.Application (functionNode :: args) ->
            case Node.value functionNode of
                Expression.FunctionOrValue [ "View" ] "htmlToFreezable" ->
                    -- New pattern: View.htmlToFreezable (Html.div [...] [...])
                    case args of
                        innerArg :: [] ->
                            isHtmlDivWithDataStatic (unwrapParenthesizedExpression innerArg)

                        _ ->
                            False

                Expression.FunctionOrValue _ "htmlToFreezable" ->
                    -- Also handle unqualified or aliased View module
                    case args of
                        innerArg :: [] ->
                            isHtmlDivWithDataStatic (unwrapParenthesizedExpression innerArg)

                        _ ->
                            False

                Expression.FunctionOrValue _ "div" ->
                    -- Legacy pattern: Html.div [...] [...] directly
                    case args of
                        attrListNode :: _ ->
                            containsDataStaticAttribute attrListNode

                        _ ->
                            False

                _ ->
                    False

        _ ->
            False


{-| Check if an expression is Html.div with data-static attribute.
-}
isHtmlDivWithDataStatic : Node Expression -> Bool
isHtmlDivWithDataStatic node =
    case Node.value node of
        Expression.Application (functionNode :: attrListNode :: _) ->
            case Node.value functionNode of
                Expression.FunctionOrValue _ "div" ->
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


{-| Get the static prefix for data-static attribute based on module name.
Shared module uses "shared:" prefix to distinguish from Route frozen views.
-}
getStaticPrefix : ModuleName -> String
getStaticPrefix moduleName =
    if moduleName == [ "Shared" ] then
        "shared:"

    else
        ""


expressionExitVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionExitVisitor node context =
    let
        contextWithDepthAndLetUpdate =
            case Node.value node of
                Expression.LambdaExpression _ ->
                    if context.lambdaDepth > 0 then
                        { context | lambdaDepth = context.lambdaDepth - 1 }

                    else
                        context

                Expression.LetExpression _ ->
                    let
                        poppedLocalLetFunctions =
                            case context.localLetFunctionsNeedingSeed of
                                _ :: remaining ->
                                    remaining

                                [] ->
                                    []
                    in
                    { context | localLetFunctionsNeedingSeed = poppedLocalLetFunctions }

                _ ->
                    context
    in
    if PersistentFieldTracking.isExitingFreezeCall node contextWithDepthAndLetUpdate.lookupTable then
        ( [], { contextWithDepthAndLetUpdate | sharedState = PersistentFieldTracking.updateOnFreezeExit contextWithDepthAndLetUpdate.sharedState } )

    else
        ( [], contextWithDepthAndLetUpdate )


{-| Extract head function name from RouteBuilder.preRender/single/serverRender record argument.

This ensures we correctly identify which function is the head function
based on what's ACTUALLY passed to RouteBuilder, not just by function name.

If the record uses a simple function reference like `{ head = seoTags }`,
we extract "seoTags". If it uses lambdas or complex expressions, we can't
safely track these.

-}
extractRouteBuilderHeadFn : Context -> List (Node Expression) -> Context
extractRouteBuilderHeadFn context args =
    case args of
        recordArg :: _ ->
            case Node.value recordArg of
                Expression.RecordExpr fields ->
                    let
                        extracted =
                            PersistentFieldTracking.extractRouteBuilderFunctions fields

                        updatedSharedState =
                            PersistentFieldTracking.setRouteBuilderHeadFn extracted.headFn context.sharedState
                    in
                    { context | sharedState = updatedSharedState }

                _ ->
                    -- Not a record literal - can't extract function names
                    context

        _ ->
            context


{-| Track field access on app.data

Uses the shared trackFieldAccessShared function from PersistentFieldTracking.
This ensures both client and server transforms use identical tracking logic.

-}
trackFieldAccess : Node Expression -> Context -> Context
trackFieldAccess node context =
    let
        updatedSharedState =
            PersistentFieldTracking.trackFieldAccessShared node context.sharedState context.lookupTable context.moduleName
    in
    { context | sharedState = updatedSharedState }


{-| Check if a function node is a call to View.freeze.
-}
isViewFreezeCall : Node Expression -> Context -> Bool
isViewFreezeCall functionNode context =
    PersistentFieldTracking.isViewFreezeCall functionNode context.lookupTable


isAppDataAccess : Node Expression -> Context -> Bool
isAppDataAccess node context =
    PersistentFieldTracking.isAppDataAccess node context.sharedState.appParamName context.sharedState.appDataBindings


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


{-| Check if app.data is passed as a whole to a function.

In CLIENT context: track as pending helper call for field usage analysis.
In FREEZE context: we don't care (it's ephemeral).

Uses shared analyzeHelperCallInClientContext from PersistentFieldTracking.

-}
checkAppDataPassedToHelper : Context -> Node Expression -> List (Node Expression) -> Context
checkAppDataPassedToHelper context functionNode args =
    -- In ephemeral context (freeze/head) - we don't care about tracking
    if (context.sharedState.freezeCallDepth > 0) || context.sharedState.inHeadFunction then
        context

    else
        let
            classification =
                PersistentFieldTracking.classifyAppDataArguments
                    functionNode
                    args
                    context.sharedState.appParamName
                    context.sharedState.appDataBindings
                    (\fn -> isViewFreezeCall fn context)
                    (\expr -> containsAppDataExpression expr context)
                    (\calledFunctionNode -> resolveCalledFunctionId calledFunctionNode context)

            result =
                PersistentFieldTracking.analyzeHelperCallInClientContext functionNode classification

            updatedSharedState =
                PersistentFieldTracking.applyHelperCallResult result context.sharedState
        in
        { context | sharedState = updatedSharedState }


{-| Check if app.data is passed to a function via pipe operator.

Handles `app.data |> fn` and `fn <| app.data` patterns.
Uses shared analyzePipedHelperCall from PersistentFieldTracking.

-}
checkAppDataPassedToHelperViaPipe : Context -> Node Expression -> Node Expression -> Context
checkAppDataPassedToHelperViaPipe context functionNode argNode =
    -- Check if the argument is app.data (or an alias)
    if not (isAppDataAccess argNode context) then
        context

    else if (context.sharedState.freezeCallDepth > 0) || context.sharedState.inHeadFunction then
        -- In ephemeral context (freeze/head) - we don't care about tracking
        context

    else
        -- In client context - use shared pipe analysis
        let
            result =
                PersistentFieldTracking.analyzePipedHelperCall (\calledFunctionNode -> resolveCalledFunctionId calledFunctionNode context) functionNode

            updatedSharedState =
                PersistentFieldTracking.applyHelperCallResult result context.sharedState
        in
        { context | sharedState = updatedSharedState }


{-| Delegate to shared isRecordAccessFunction function.
-}
isRecordAccessFunction : Node Expression -> Bool
isRecordAccessFunction =
    PersistentFieldTracking.isRecordAccessFunction


{-| Extract all ranges where "Data" appears as a type reference in a type annotation.
-}
extractDataTypeReferences : Node TypeAnnotation -> List Range
extractDataTypeReferences =
    PersistentFieldTracking.extractDataTypeRanges


{-| Check if one range fully contains another range.
-}
rangeContains : Range -> Range -> Bool
rangeContains outer inner =
    let
        outerStartsBefore =
            (outer.start.row < inner.start.row)
                || (outer.start.row == inner.start.row && outer.start.column <= inner.start.column)

        outerEndsAfter =
            (outer.end.row > inner.end.row)
                || (outer.end.row == inner.end.row && outer.end.column >= inner.end.column)
    in
    outerStartsBefore && outerEndsAfter


deferredHelperCallSeedingErrors : Context -> List (Error {})
deferredHelperCallSeedingErrors context =
    let
        orderedDeferredCalls =
            List.reverse context.deferredHelperCalls

        freezeKnowledgeAtEnd =
            freezeKnowledge context

        step deferredCall ( nextSeedIndex, injectedFunctions, errors ) =
            if FreezeHelperPlanning.functionContainsFreeze freezeKnowledgeAtEnd deferredCall.calleeFunctionId then
                let
                    ( seedExpression, nextSeedIndexAfter ) =
                        if usesHelperFrozenIdsForFunction context deferredCall.callerFunctionName then
                            ( "("
                                ++ currentFunctionFidParamNameFor context deferredCall.callerFunctionName
                                ++ " ++ \":"
                                ++ String.fromInt nextSeedIndex
                                ++ "\")"
                            , nextSeedIndex + 1
                            )

                        else
                            let
                                seedPrefix =
                                    getStaticPrefix context.moduleName
                            in
                            ( "\"" ++ seedPrefix ++ String.fromInt nextSeedIndex ++ "\""
                            , nextSeedIndex + 1
                            )

                    insertionFix =
                        case deferredCall.firstArgRange of
                            Just firstArgRange ->
                                Review.Fix.insertAt firstArgRange.start (seedExpression ++ " ")

                            Nothing ->
                                Review.Fix.insertAt deferredCall.functionRange.end (" " ++ seedExpression)

                    declarationFixes =
                        if usesHelperFrozenIdsForFunction context deferredCall.callerFunctionName
                            && not (Set.member deferredCall.callerFunctionName injectedFunctions) then
                            helperFidInjectionFixesForFunction context deferredCall.callerFunctionName

                        else
                            []

                    nextInjectedFunctions =
                        if List.isEmpty declarationFixes then
                            injectedFunctions

                        else
                            Set.insert deferredCall.callerFunctionName injectedFunctions
                in
                ( nextSeedIndexAfter
                , nextInjectedFunctions
                , Rule.errorWithFix
                    { message = "Server codemod: pass frozen ID to helper call"
                    , details = [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze." ]
                    }
                    deferredCall.callRange
                    (insertionFix :: declarationFixes)
                    :: errors
                )

            else
                ( nextSeedIndex, injectedFunctions, errors )
    in
    orderedDeferredCalls
        |> List.foldl step ( context.helperCallSeedIndex, context.injectedFidFunctions, [] )
        |> (\( _, _, errors ) -> List.reverse errors)



{-| Final evaluation - generate Ephemeral/Data split and ephemeralToData function.

The formula is: ephemeral = allFields - clientUsedFields

This is the aggressive approach that aligns with the client-side transform.
Pending helper calls are resolved here against the now-complete helperFunctions dict.
If any helper call can't be resolved (unknown function or untrackable helper), we
mark all fields as persistent (safe fallback).

-}
finalEvaluation : Context -> List (Error {})
finalEvaluation context =
    deferredHelperCallSeedingErrors context
        ++
            (let
                -- Only apply transformations to Route modules (Route.Index, Route.Blog.Slug_, etc.)
                -- Uses shared function to ensure agreement with StaticViewTransform
                isRouteModule =
                    PersistentFieldTracking.isRouteModule context.moduleName
             in
             -- Skip non-Route modules (Site.elm, Shared.elm, etc.) to avoid disagreement with client transform
             if not isRouteModule then
                 []

             else if context.hasEphemeralType then
                 -- Skip if transformation was already applied (Ephemeral type exists)
                 []

             else
                 case context.dataTypeRange of
                     Nothing ->
                         []

                     Just range ->
                         let
                             -- All field names from the Data type
                             allFieldNames =
                                 PersistentFieldTracking.extractFieldNames context.sharedState.dataTypeFields

                             -- Compute head function fields for non-conventional naming correction
                             -- This uses the same logic as StaticViewTransform to ensure agreement
                             headFunctionFields =
                                 PersistentFieldTracking.computeHeadFunctionFields context.sharedState

                             -- Compute ephemeral fields using shared logic with correction
                             -- This ensures agreement with StaticViewTransform's field computation
                             ephemeralResult =
                                 PersistentFieldTracking.computeEphemeralFieldsWithCorrection
                                     { allFieldNames = allFieldNames
                                     , clientUsedFields = context.sharedState.clientUsedFields
                                     , pendingHelperCalls = context.sharedState.pendingHelperCalls
                                     , helperFunctions = context.sharedState.helperFunctions
                                     , headFunctionFields = headFunctionFields
                                     , markAllFieldsAsUsed = context.sharedState.markAllFieldsAsUsed
                                     }

                             ephemeralFields =
                                 ephemeralResult.ephemeralFields

                             -- Persistent fields for the new Data type
                             persistentFieldDefs =
                                 context.sharedState.dataTypeFields
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
                                         ++ (context.sharedState.dataTypeFields
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
                                 dataSignatureFixes =
                                     case ( context.dataFunctionSignatureRange, context.dataFunctionSignature ) of
                                         ( Just sigRange, Just sigStr ) ->
                                             -- Replace "Data" with "Ephemeral" in the signature
                                             -- The data function returns BackendTask ... Data, we need it to return Ephemeral
                                             let
                                                 updatedSig =
                                                     String.replace " Data" " Ephemeral" sigStr
                                             in
                                             if updatedSig /= sigStr then
                                                 [ Review.Fix.replaceRangeBy sigRange updatedSig ]

                                             else
                                                 []

                                         _ ->
                                             []

                                 -- Fix Data constructor uses (e.g., map4 Data -> map4 Ephemeral)
                                 dataConstructorFixes =
                                     context.dataConstructorRanges
                                         |> List.map
                                             (\constructorRange ->
                                                 Review.Fix.replaceRangeBy constructorRange "Ephemeral"
                                             )

                                 -- Fix Data type references in function signatures (e.g., App Data -> App Ephemeral)
                                 -- Exclude references that fall within the data function's signature range,
                                 -- since that range is already handled by dataSignatureFixes (which replaces
                                 -- the entire annotation). Including both would create overlapping fix ranges
                                 -- that elm-review rejects.
                                 dataTypeReferenceFixes =
                                     context.dataTypeReferenceRanges
                                         |> List.filter
                                             (\refRange ->
                                                 case context.dataFunctionSignatureRange of
                                                     Just sigRange ->
                                                         not (rangeContains sigRange refRange)

                                                     Nothing ->
                                                         True
                                             )
                                         |> List.map
                                             (\refRange ->
                                                 Review.Fix.replaceRangeBy refRange "Ephemeral"
                                             )

                                 -- Fix module exports to include Ephemeral
                                 exportFixes =
                                     case context.dataExportRange of
                                         Just exportRange ->
                                             -- Insert ", Ephemeral" after "Data" in exports
                                             [ Review.Fix.insertAt exportRange.end ", Ephemeral, ephemeralToData" ]

                                         Nothing ->
                                             []

                                 -- Combine ALL fixes into a single errorWithFix so they are applied
                                 -- atomically by elm-review. If fixes are split across multiple errors,
                                 -- elm-review applies one fix at a time and re-analyzes between each.
                                 -- After the Data type split is applied, hasEphemeralType becomes True
                                 -- on re-analysis, which would prevent the remaining fixes (exports,
                                 -- constructors, signatures) from ever being generated.
                                 allFixes =
                                     [ Review.Fix.replaceRangeBy range fullReplacement ]
                                         ++ dataSignatureFixes
                                         ++ dataConstructorFixes
                                         ++ dataTypeReferenceFixes
                                         ++ exportFixes

                                 -- Emit EPHEMERAL_FIELDS_JSON for the codegen to pick up
                                 ephemeralFieldsJson =
                                     "EPHEMERAL_FIELDS_JSON:{\"module\":\""
                                         ++ String.join "." context.moduleName
                                         ++ "\",\"ephemeralFields\":["
                                         ++ (ephemeralFields |> Set.toList |> List.map (\f -> "\"" ++ f ++ "\"") |> String.join ",")
                                         ++ "]}"

                                 ephemeralFieldsError =
                                     Rule.error
                                         { message = ephemeralFieldsJson
                                         , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                         }
                                         range
                             in
                             [ ephemeralFieldsError
                             , Rule.errorWithFix
                                     { message = "Server codemod: split Data into Ephemeral and Data"
                                     , details =
                                         [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                         , "Ephemeral fields: " ++ String.join ", " (Set.toList ephemeralFields)
                                         , "Generating ephemeralToData conversion function for wire encoding."
                                         ]
                                     }
                                     range
                                     allFixes
                             ]
            )
