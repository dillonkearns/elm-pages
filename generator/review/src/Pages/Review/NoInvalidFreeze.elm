module Pages.Review.NoInvalidFreeze exposing (rule)

{-| This rule ensures that frozen view functions are only called from Route modules
and that model (or values derived from model) is not referenced inside freeze calls.

Frozen views (View.freeze) are transformed by elm-review during the client-side build.
This transformation only works for Route modules. Calling these functions from other
modules (like Shared.elm or helper modules) will NOT enable DCE - the heavy dependencies
will still be in the client bundle.

This rule also tracks taint across module boundaries by collecting function taint
signatures from each module. For example:

    -- Helpers.elm
    formatUser user = user.name

    -- Route/Index.elm
    View.freeze (text (Helpers.formatUser model.user))  -- ERROR: tainted!

The rule detects that `model.user` is tainted and flows through `formatUser`.

@docs rule

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Pages.Review.TaintTracking as Taint
    exposing
        ( Nonempty(..)
        , TaintStatus(..)
        , addBindingsToScope
        , emptyBindings
        , extractBindingsFromPattern
        , nonemptyCons
        , nonemptyPop
        )
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


{-| Convert a range to a comparable tuple for Set storage.
-}
rangeToComparable : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> ( ( Int, Int ), ( Int, Int ) )
rangeToComparable range =
    ( ( range.start.row, range.start.column ), ( range.end.row, range.end.column ) )



-- PROJECT CONTEXT


{-| Information about a function's taint behavior.

  - `capturesTaint`: True if the function body references tainted values from outer scope
  - `paramsThatTaintResult`: Set of parameter indices (0-based) that flow through to the result

-}
type alias FunctionTaintInfo =
    { capturesTaint : Bool
    , paramsThatTaintResult : Set Int
    }


{-| Project-level context: accumulated function taint info from all modules.
-}
type alias ProjectContext =
    { functionTaintInfo : Dict ( ModuleName, String ) FunctionTaintInfo
    }


initialProjectContext : ProjectContext
initialProjectContext =
    { functionTaintInfo = Dict.empty
    }



-- MODULE CONTEXT


type alias ModuleContext =
    { lookupTable : ModuleNameLookupTable
    , moduleName : ModuleName
    , freezeCallDepth : Int
    , appParamName : Maybe String
    , modelParamName : Maybe String
    , bindings : Nonempty (Dict String TaintStatus)
    , projectFunctions : Dict ( ModuleName, String ) FunctionTaintInfo
    , collectedFunctions : Dict String FunctionTaintInfo
    , reportedRanges : Set ( ( Int, Int ), ( Int, Int ) )

    -- Tainted context depth: tracks when we're inside a conditional (if/case) that
    -- depends on model. When > 0, we're in a tainted context and should report error.
    , taintedContextDepth : Int
    }


{-| Reports uses of tainted values inside View.freeze, including values that
flow through helper functions from other modules.
-}
rule : Rule
rule =
    Rule.newProjectRuleSchema "Pages.Review.NoInvalidFreeze" initialProjectContext
        |> Rule.withContextFromImportedModules
        |> Rule.withModuleVisitor moduleVisitor
        |> Rule.withModuleContextUsingContextCreator
            { fromProjectToModule = fromProjectToModule
            , fromModuleToProject = fromModuleToProject
            , foldProjectContexts = foldProjectContexts
            }
        |> Rule.fromProjectRuleSchema


moduleVisitor :
    Rule.ModuleRuleSchema {} ModuleContext
    -> Rule.ModuleRuleSchema { hasAtLeastOneVisitor : () } ModuleContext
moduleVisitor schema =
    schema
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.withLetDeclarationEnterVisitor letDeclarationEnterVisitor
        |> Rule.withCaseBranchEnterVisitor caseBranchEnterVisitor
        |> Rule.withCaseBranchExitVisitor caseBranchExitVisitor


fromProjectToModule : Rule.ContextCreator ProjectContext ModuleContext
fromProjectToModule =
    Rule.initContextCreator
        (\lookupTable moduleName projectContext ->
            { lookupTable = lookupTable
            , moduleName = moduleName
            , freezeCallDepth = 0
            , appParamName = Nothing
            , modelParamName = Nothing
            , bindings = emptyBindings
            , projectFunctions = projectContext.functionTaintInfo
            , collectedFunctions = Dict.empty
            , reportedRanges = Set.empty
            , taintedContextDepth = 0
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


fromModuleToProject : Rule.ContextCreator ModuleContext ProjectContext
fromModuleToProject =
    Rule.initContextCreator
        (\moduleName moduleContext ->
            { functionTaintInfo =
                -- Use Dict.foldl for O(n) instead of toList |> map |> fromList which is O(n log n)
                Dict.foldl
                    (\name info acc -> Dict.insert ( moduleName, name ) info acc)
                    Dict.empty
                    moduleContext.collectedFunctions
            }
        )
        |> Rule.withModuleName


foldProjectContexts : ProjectContext -> ProjectContext -> ProjectContext
foldProjectContexts a b =
    { functionTaintInfo = Dict.union a.functionTaintInfo b.functionTaintInfo
    }



-- HELPERS


{-| Report an error if we haven't already reported at this range.
Returns the error (if new) and the updated context with the range tracked.
-}
reportErrorIfNew :
    { start : { row : Int, column : Int }, end : { row : Int, column : Int } }
    -> Error {}
    -> ModuleContext
    -> ( List (Error {}), ModuleContext )
reportErrorIfNew range error context =
    let
        rangeKey =
            rangeToComparable range
    in
    if Set.member rangeKey context.reportedRanges then
        ( [], context )

    else
        ( [ error ]
        , { context | reportedRanges = Set.insert rangeKey context.reportedRanges }
        )


{-| Collect errors from a list, deduplicating by range.
-}
collectErrors :
    List ( { start : { row : Int, column : Int }, end : { row : Int, column : Int } }, Error {} )
    -> ModuleContext
    -> ( List (Error {}), ModuleContext )
collectErrors errorPairs context =
    List.foldl
        (\( range, error ) ( accErrors, accContext ) ->
            let
                ( newErrors, newContext ) =
                    reportErrorIfNew range error accContext
            in
            ( accErrors ++ newErrors, newContext )
        )
        ( [], context )
        errorPairs


{-| Look up a binding in the context's scope stack.
-}
lookupBinding : String -> ModuleContext -> Maybe TaintStatus
lookupBinding name context =
    Taint.lookupBinding name context.bindings


{-| Add bindings to the current scope.
-}
addBindingsToCurrentScope : List ( String, TaintStatus ) -> ModuleContext -> ModuleContext
addBindingsToCurrentScope newBindings context =
    { context | bindings = addBindingsToScope newBindings context.bindings }


{-| Push a new empty scope onto the stack.
-}
pushScope : ModuleContext -> ModuleContext
pushScope context =
    { context | bindings = nonemptyCons Dict.empty context.bindings }


{-| Pop the top scope from the stack.
-}
popScope : ModuleContext -> ModuleContext
popScope context =
    case nonemptyPop context.bindings of
        Just newBindings ->
            { context | bindings = newBindings }

        Nothing ->
            context


{-| Get a TaintContext for use with analyzeExpressionTaint.
-}
toTaintContext : ModuleContext -> Taint.TaintContext
toTaintContext context =
    { modelParamName = context.modelParamName
    , bindings = context.bindings
    }


{-| Analyze expression taint using the shared module.
-}
analyzeExpressionTaint : ModuleContext -> Node Expression -> TaintStatus
analyzeExpressionTaint context =
    Taint.analyzeExpressionTaint (toTaintContext context)


{-| Runtime app fields that don't exist at build time.
-}
runtimeAppFields : List String
runtimeAppFields =
    [ "action"
    , "navigation"
    , "pageFormState"
    , "concurrentSubmissions"
    , "submit"
    , "url"
    ]


{-| Check if a module name is a Route module (Route.Something, Route.Blog.Slug_, etc.)
-}
isRouteModule : ModuleName -> Bool
isRouteModule moduleName =
    case moduleName of
        "Route" :: _ :: _ ->
            True

        _ ->
            False


{-| Check if a module name is allowed to use frozen view functions.
This includes Route modules and the View module (which provides helper functions
that are ultimately called from Route modules).
-}
isAllowedModule : ModuleName -> Bool
isAllowedModule moduleName =
    isRouteModule moduleName || moduleName == [ "View" ] || moduleName == [ "Shared" ]


{-| Frozen view functions that should only be called from Route modules.
-}
staticFunctionNames : List String
staticFunctionNames =
    [ "freeze" ]





-- VISITORS


declarationEnterVisitor : Node Declaration -> ModuleContext -> ( List (Error {}), ModuleContext )
declarationEnterVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                functionDecl =
                    Node.value function.declaration

                functionName =
                    Node.value functionDecl.name

                -- Extract parameter names
                paramNames =
                    List.filterMap extractPatternName functionDecl.arguments

                -- Analyze which parameters flow through to the result
                -- We create a context where each param is marked as "tainted" to track flow
                paramFlowContext =
                    { modelParamName = Nothing
                    , bindings =
                        paramNames
                            |> List.map (\name -> ( name, Tainted ))
                            |> (\bindings -> addBindingsToScope bindings emptyBindings)
                    }

                -- Analyze body - if result is tainted, some param flowed through
                bodyTaint =
                    Taint.analyzeExpressionTaint paramFlowContext functionDecl.expression

                -- If the body is tainted (with params as tainted), all params could flow through
                -- A more sophisticated analysis would track exactly which params flow
                paramsThatTaint =
                    if bodyTaint == Tainted then
                        List.range 0 (List.length functionDecl.arguments - 1)
                            |> Set.fromList

                    else
                        Set.empty

                -- Also check if function captures tainted values from outer scope
                -- (using the actual context with model param info)
                capturesTaint =
                    analyzeExpressionTaint context functionDecl.expression == Tainted

                functionInfo =
                    { capturesTaint = capturesTaint
                    , paramsThatTaintResult = paramsThatTaint
                    }

                newCollected =
                    Dict.insert functionName functionInfo context.collectedFunctions
            in
            if functionName == "view" then
                -- Extract app and model param names for view function
                let
                    arguments =
                        functionDecl.arguments

                    maybeAppParam =
                        List.head arguments
                            |> Maybe.andThen extractPatternName

                    maybeModelParam =
                        arguments
                            |> List.drop 2
                            |> List.head
                            |> Maybe.andThen extractPatternName
                in
                ( []
                , { context
                    | appParamName = maybeAppParam
                    , modelParamName = maybeModelParam
                    , collectedFunctions = newCollected
                  }
                )

            else
                ( [], { context | collectedFunctions = newCollected } )

        _ ->
            ( [], context )


{-| Extract a single name from a pattern.
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


expressionEnterVisitor : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
expressionEnterVisitor node context =
    -- First, track entering tainted conditionals (if/case)
    let
        contextWithTaintedContext =
            case Node.value node of
                Expression.IfBlock cond _ _ ->
                    let
                        condTaint =
                            analyzeExpressionTaint context cond
                    in
                    if condTaint == Tainted then
                        { context | taintedContextDepth = context.taintedContextDepth + 1 }

                    else
                        context

                Expression.CaseExpression caseBlock ->
                    let
                        scrutineeTaint =
                            analyzeExpressionTaint context caseBlock.expression
                    in
                    if scrutineeTaint == Tainted then
                        { context | taintedContextDepth = context.taintedContextDepth + 1 }

                    else
                        context

                _ ->
                    context
    in
    case Node.value node of
        Expression.Application (functionNode :: _) ->
            -- Check if this is a call to a frozen view function
            case checkFrozenViewFunctionCall functionNode contextWithTaintedContext of
                Just scopeError ->
                    -- Report scope error and don't enter freeze mode (no point checking taint)
                    ( [ scopeError ], contextWithTaintedContext )

                Nothing ->
                    -- No scope error - check if entering freeze and track taint
                    let
                        isEnteringFreeze =
                            case ModuleNameLookupTable.moduleNameFor contextWithTaintedContext.lookupTable functionNode of
                                Just [ "View" ] ->
                                    case Node.value functionNode of
                                        Expression.FunctionOrValue _ "freeze" ->
                                            True

                                        _ ->
                                            False

                                _ ->
                                    False

                        contextWithFreeze =
                            if isEnteringFreeze then
                                { contextWithTaintedContext | freezeCallDepth = contextWithTaintedContext.freezeCallDepth + 1 }

                            else
                                contextWithTaintedContext

                        -- Check if we're entering a View.freeze while inside a tainted conditional
                        -- (only report on first entry to freeze, not on nested freezes)
                        taintedConditionalError =
                            if isEnteringFreeze && contextWithTaintedContext.freezeCallDepth == 0 && contextWithTaintedContext.taintedContextDepth > 0 then
                                -- Just entered freeze while inside tainted conditional
                                [ freezeInTaintedContextError (Node.range functionNode) ]

                            else
                                []
                    in
                    if contextWithFreeze.freezeCallDepth > 0 then
                        let
                            ( taintErrors, finalContext ) =
                                checkTaintedReference node contextWithFreeze
                        in
                        ( taintedConditionalError ++ taintErrors, finalContext )

                    else
                        ( taintedConditionalError, contextWithFreeze )

        _ ->
            -- Not a function application - check taint if in freeze
            if contextWithTaintedContext.freezeCallDepth > 0 then
                checkTaintedReference node contextWithTaintedContext

            else
                ( [], contextWithTaintedContext )


{-| Check if a function call is to a frozen view function and if the current module is allowed.
Returns Just error if not allowed, Nothing if allowed or not a frozen view function.
-}
checkFrozenViewFunctionCall : Node Expression -> ModuleContext -> Maybe (Error {})
checkFrozenViewFunctionCall functionNode context =
    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
        Just [ "View" ] ->
            case Node.value functionNode of
                Expression.FunctionOrValue _ name ->
                    if List.member name staticFunctionNames && not (isAllowedModule context.moduleName) then
                        Just (frozenViewScopeError (Node.range functionNode) ("View." ++ name))

                    else
                        Nothing

                _ ->
                    Nothing

        _ ->
            Nothing


expressionExitVisitor : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
expressionExitVisitor node context =
    -- Track exiting tainted conditionals (if/case)
    let
        contextWithTaintedContextUpdate =
            case Node.value node of
                Expression.IfBlock cond _ _ ->
                    let
                        condTaint =
                            analyzeExpressionTaint context cond
                    in
                    if condTaint == Tainted && context.taintedContextDepth > 0 then
                        { context | taintedContextDepth = context.taintedContextDepth - 1 }

                    else
                        context

                Expression.CaseExpression caseBlock ->
                    let
                        scrutineeTaint =
                            analyzeExpressionTaint context caseBlock.expression
                    in
                    if scrutineeTaint == Tainted && context.taintedContextDepth > 0 then
                        { context | taintedContextDepth = context.taintedContextDepth - 1 }

                    else
                        context

                _ ->
                    context
    in
    case Node.value node of
        Expression.Application (functionNode :: _) ->
            case ModuleNameLookupTable.moduleNameFor contextWithTaintedContextUpdate.lookupTable functionNode of
                Just [ "View" ] ->
                    case Node.value functionNode of
                        Expression.FunctionOrValue _ "freeze" ->
                            ( [], { contextWithTaintedContextUpdate | freezeCallDepth = max 0 (contextWithTaintedContextUpdate.freezeCallDepth - 1) } )

                        _ ->
                            ( [], contextWithTaintedContextUpdate )

                _ ->
                    ( [], contextWithTaintedContextUpdate )

        _ ->
            ( [], contextWithTaintedContextUpdate )


letDeclarationEnterVisitor : Node Expression.LetBlock -> Node Expression.LetDeclaration -> ModuleContext -> ( List (Error {}), ModuleContext )
letDeclarationEnterVisitor _ letDeclNode context =
    case Node.value letDeclNode of
        Expression.LetFunction function ->
            let
                functionDecl =
                    Node.value function.declaration

                functionName =
                    Node.value functionDecl.name

                bodyTaint =
                    analyzeExpressionTaint context functionDecl.expression
            in
            ( [], addBindingsToCurrentScope [ ( functionName, bodyTaint ) ] context )

        Expression.LetDestructuring pattern expr ->
            let
                exprTaint =
                    analyzeExpressionTaint context expr

                bindings =
                    extractBindingsFromPattern exprTaint pattern
            in
            ( [], addBindingsToCurrentScope bindings context )


caseBranchEnterVisitor : Node Expression.CaseBlock -> ( Node Pattern, Node Expression ) -> ModuleContext -> ( List (Error {}), ModuleContext )
caseBranchEnterVisitor caseBlockNode ( patternNode, _ ) context =
    let
        caseBlock =
            Node.value caseBlockNode

        caseTaint =
            analyzeExpressionTaint context caseBlock.expression

        patternBindings =
            extractBindingsFromPattern caseTaint patternNode
    in
    ( [], pushScope context |> addBindingsToCurrentScope patternBindings )


caseBranchExitVisitor : Node Expression.CaseBlock -> ( Node Pattern, Node Expression ) -> ModuleContext -> ( List (Error {}), ModuleContext )
caseBranchExitVisitor _ _ context =
    ( [], popScope context )



-- TAINT CHECKING


{-| Check if an expression inside freeze is tainted, including cross-module function calls.
Uses deduplication to avoid reporting multiple errors at the same location.
-}
checkTaintedReference : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
checkTaintedReference node context =
    case Node.value node of
        -- Check for tainted local variable
        Expression.FunctionOrValue [] varName ->
            if context.modelParamName == Just varName then
                -- model itself is handled by more specific checks (RecordAccess)
                ( [], context )

            else
                case lookupBinding varName context of
                    Just Tainted ->
                        reportErrorIfNew (Node.range node)
                            (taintedValueError (Node.range node) varName)
                            context

                    _ ->
                        ( [], context )

        -- Check for model.field or taintedVar.field
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] varName ->
                    case lookupBinding varName context of
                        Just Tainted ->
                            reportErrorIfNew (Node.range node)
                                (taintedValueError (Node.range node) varName)
                                context

                        Just Pure ->
                            ( [], context )

                        Nothing ->
                            if context.modelParamName == Just varName then
                                reportErrorIfNew (Node.range node)
                                    (modelInFreezeError (Node.range node))
                                    context

                            else if context.appParamName == Just varName && List.member fieldName runtimeAppFields then
                                reportErrorIfNew (Node.range node)
                                    (runtimeAppFieldError (Node.range node) fieldName)
                                    context

                            else
                                ( [], context )

                _ ->
                    ( [], context )

        -- Check for cross-module function calls with tainted arguments
        Expression.Application (functionNode :: args) ->
            checkCrossModuleCall functionNode args context

        -- Pipe operator
        Expression.OperatorApplication "|>" _ leftExpr rightExpr ->
            checkPipeExpression leftExpr rightExpr context

        -- Case expression
        Expression.CaseExpression caseBlock ->
            checkCaseExpression caseBlock.expression context

        _ ->
            ( [], context )


{-| Check if a cross-module function call passes tainted values.
-}
checkCrossModuleCall : Node Expression -> List (Node Expression) -> ModuleContext -> ( List (Error {}), ModuleContext )
checkCrossModuleCall functionNode args context =
    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
        Just moduleName ->
            case Node.value functionNode of
                Expression.FunctionOrValue _ functionName ->
                    let
                        key =
                            ( moduleName, functionName )
                    in
                    case Dict.get key context.projectFunctions of
                        Just functionInfo ->
                            -- Check if any tainted arg is passed to a param that taints result
                            args
                                |> List.indexedMap
                                    (\idx argNode ->
                                        if Set.member idx functionInfo.paramsThatTaintResult then
                                            let
                                                argTaint =
                                                    analyzeExpressionTaint context argNode
                                            in
                                            if argTaint == Tainted then
                                                Just
                                                    ( Node.range argNode
                                                    , crossModuleTaintError (Node.range argNode) functionName
                                                    )

                                            else
                                                Nothing

                                        else
                                            Nothing
                                    )
                                |> List.filterMap identity
                                |> (\errorPairs -> collectErrors errorPairs context)

                        Nothing ->
                            -- Unknown function (external package) - no error
                            ( [], context )

                _ ->
                    ( [], context )

        Nothing ->
            ( [], context )


{-| Check pipe expressions for tainted values.
-}
checkPipeExpression : Node Expression -> Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
checkPipeExpression leftExpr rightExpr context =
    case Node.value rightExpr of
        Expression.RecordAccessFunction fieldName ->
            case Node.value leftExpr of
                Expression.FunctionOrValue [] varName ->
                    if context.modelParamName == Just varName then
                        reportErrorIfNew (Node.range leftExpr)
                            (accessorOnModelError (Node.range leftExpr))
                            context

                    else if context.appParamName == Just varName && List.member fieldName runtimeAppFields then
                        reportErrorIfNew (Node.range leftExpr)
                            (accessorOnRuntimeAppFieldError (Node.range leftExpr) fieldName)
                            context

                    else
                        case lookupBinding varName context of
                            Just Tainted ->
                                reportErrorIfNew (Node.range leftExpr)
                                    (taintedValueError (Node.range leftExpr) varName)
                                    context

                            _ ->
                                ( [], context )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )


{-| Check case expressions on tainted values.
-}
checkCaseExpression : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
checkCaseExpression exprNode context =
    case Node.value exprNode of
        Expression.FunctionOrValue [] varName ->
            if context.modelParamName == Just varName then
                reportErrorIfNew (Node.range exprNode)
                    (caseOnModelError (Node.range exprNode))
                    context

            else if context.appParamName == Just varName then
                reportErrorIfNew (Node.range exprNode)
                    (caseOnAppError (Node.range exprNode))
                    context

            else
                case lookupBinding varName context of
                    Just Tainted ->
                        reportErrorIfNew (Node.range exprNode)
                            (caseOnTaintedValueError (Node.range exprNode) varName)
                            context

                    _ ->
                        ( [], context )

        _ ->
            ( [], context )



-- ERROR HELPERS


taintedValueError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
taintedValueError range varName =
    Rule.error
        { message = "Tainted value `" ++ varName ++ "` used inside View.freeze"
        , details =
            [ "`" ++ varName ++ "` depends on `model` or other runtime data that doesn't exist at build time."
            , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
            , "To fix this, either:"
            , "1. Move the model-dependent content outside of `View.freeze`, or"
            , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
            ]
        }
        range


modelInFreezeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
modelInFreezeError range =
    Rule.error
        { message = "Model referenced inside View.freeze"
        , details =
            [ "Frozen content is rendered at build time when no model state exists."
            , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
            , "To fix this, either:"
            , "1. Move the model-dependent content outside of `View.freeze`, or"
            , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
            ]
        }
        range


runtimeAppFieldError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
runtimeAppFieldError range fieldName =
    Rule.error
        { message = "Runtime field `" ++ fieldName ++ "` accessed inside View.freeze"
        , details =
            [ "`app." ++ fieldName ++ "` is runtime-only data that doesn't exist at build time."
            , "Frozen content is rendered once at build time, so runtime fields like `action`, `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
            , "To fix this, either:"
            , "1. Move the runtime-dependent content outside of `View.freeze`, or"
            , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.sharedData`, `app.routeParams`, `app.path`"
            ]
        }
        range


accessorOnModelError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
accessorOnModelError range =
    Rule.error
        { message = "Accessor on model inside View.freeze"
        , details =
            [ "Frozen content is rendered at build time when no model state exists."
            , "Using `model |> .field` inside `View.freeze` accesses model data that won't exist at build time."
            , "To fix this, move the model-dependent content outside of `View.freeze`."
            ]
        }
        range


accessorOnRuntimeAppFieldError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
accessorOnRuntimeAppFieldError range fieldName =
    Rule.error
        { message = "Accessor on runtime app field inside View.freeze"
        , details =
            [ "`app |> ." ++ fieldName ++ "` accesses runtime-only data that doesn't exist at build time."
            , "Frozen content is rendered once at build time, so runtime fields are not available."
            , "To fix this, move this content outside of `View.freeze`."
            ]
        }
        range


caseOnModelError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
caseOnModelError range =
    Rule.error
        { message = "Pattern match on model inside View.freeze"
        , details =
            [ "Frozen content is rendered at build time when no model state exists."
            , "Using `case model of` inside `View.freeze` depends on model data that won't exist at build time."
            , "To fix this, move the model-dependent content outside of `View.freeze`."
            ]
        }
        range


caseOnAppError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
caseOnAppError range =
    Rule.error
        { message = "Pattern match on app inside View.freeze"
        , details =
            [ "Using `case app of` inside `View.freeze` accesses the full app record which contains runtime-only fields."
            , "Frozen content is rendered once at build time, and runtime fields like `action`, `navigation` don't exist yet."
            , "To fix this, either:"
            , "1. Move this content outside of `View.freeze`, or"
            , "2. Access specific build-time fields like `app.data` or `app.routeParams` instead"
            ]
        }
        range


caseOnTaintedValueError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
caseOnTaintedValueError range varName =
    Rule.error
        { message = "Pattern match on tainted value `" ++ varName ++ "` inside View.freeze"
        , details =
            [ "`" ++ varName ++ "` depends on `model` or other runtime data that doesn't exist at build time."
            , "Using `case " ++ varName ++ " of` inside `View.freeze` depends on data that won't exist at build time."
            , "To fix this, move the model-dependent content outside of `View.freeze`."
            ]
        }
        range


crossModuleTaintError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
crossModuleTaintError range functionName =
    Rule.error
        { message = "Tainted value passed to `" ++ functionName ++ "` inside View.freeze"
        , details =
            [ "This argument depends on `model` or other runtime data, and `" ++ functionName ++ "` passes it through to the result."
            , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
            , "To fix this, either:"
            , "1. Move the model-dependent content outside of `View.freeze`, or"
            , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
            ]
        }
        range


frozenViewScopeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
frozenViewScopeError range functionName =
    Rule.error
        { message = "`" ++ functionName ++ "` can only be called from Route modules"
        , details =
            [ "Frozen view functions like `" ++ functionName ++ "` are transformed by elm-review during the client-side build to enable dead code elimination (DCE)."
            , "This transformation only works for Route modules (Route.Index, Route.Blog.Slug_, etc.). Calling these functions from other modules like Shared.elm or helper modules will NOT enable DCE - the heavy dependencies will still be included in the client bundle."
            , "To fix this, either:"
            , "1. Move the `" ++ functionName ++ "` call into a Route module, or"
            , "2. Create a helper function that returns data/Html and call `" ++ functionName ++ "` in the Route module"
            ]
        }
        range


freezeInTaintedContextError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
freezeInTaintedContextError range =
    Rule.error
        { message = "View.freeze inside conditionally-executed code path"
        , details =
            [ "This View.freeze is inside an if/case that depends on `model`."
            , "The server renders at build time with initial model state, but the client may have different state."
            , "This can cause server/client mismatch where different freeze indices are rendered."
            , "Move the conditional logic outside of View.freeze, or ensure the condition only depends on build-time data."
            ]
        }
        range
