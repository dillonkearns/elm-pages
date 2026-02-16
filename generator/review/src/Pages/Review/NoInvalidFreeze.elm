module Pages.Review.NoInvalidFreeze exposing (rule)

{-| This rule ensures that frozen view functions are only called from allowed modules
(Route modules, View.elm, and Shared.elm) and that model (or values derived from model)
is not referenced inside freeze calls.

Frozen views (View.freeze) are transformed by elm-review during the client-side build.
This transformation only works for Route modules, View.elm, and Shared.elm. Calling
these functions from helper modules will NOT enable DCE - the heavy dependencies will
still be in the client bundle.

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
import Elm.Syntax.Range exposing (Range)
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
rangeToComparable : Range -> ( ( Int, Int ), ( Int, Int ) )
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
    , sharedModelParamName : Maybe String
    , modelParamName : Maybe String
    , bindings : Nonempty (Dict String TaintStatus)
    , projectFunctions : Dict ( ModuleName, String ) FunctionTaintInfo
    , collectedFunctions : Dict String FunctionTaintInfo
    , reportedRanges : Set ( ( Int, Int ), ( Int, Int ) )

    -- Tainted context: tracks when we're inside a conditional (if/case) that
    -- depends on model. When the stack is not empty, we're in a tainted context and should report error.
    , taintedContext : List Range
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
        |> Rule.withExpressionExitVisitor (\node context -> ( [], expressionExitVisitor node context ))
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
            , sharedModelParamName = Nothing
            , modelParamName = Nothing
            , bindings = emptyBindings
            , projectFunctions = projectContext.functionTaintInfo
            , collectedFunctions = Dict.empty
            , reportedRanges = Set.empty
            , taintedContext = []
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
    Range
    -> Error {}
    -> ModuleContext
    -> List (Error {})
    -> ( List (Error {}), ModuleContext )
reportErrorIfNew range error context accErrors =
    let
        rangeKey =
            rangeToComparable range
    in
    if Set.member rangeKey context.reportedRanges then
        ( accErrors, context )

    else
        ( error :: accErrors
        , { context | reportedRanges = Set.insert rangeKey context.reportedRanges }
        )


{-| Collect errors from a list, deduplicating by range.
-}
collectErrors :
    List ( Range, Error {} )
    -> ModuleContext
    -> List (Error {})
    -> ( List (Error {}), ModuleContext )
collectErrors errorPairs context accErrors =
    List.foldl
        (\( range, error ) ( accErrors_, accContext ) ->
            reportErrorIfNew range error accContext accErrors_
        )
        ( accErrors, context )
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
    , sharedModelParamName = context.sharedModelParamName
    , bindings = context.bindings
    }


{-| Analyze expression taint using the shared module.
-}
analyzeExpressionTaint : ModuleContext -> Node Expression -> TaintStatus
analyzeExpressionTaint context =
    Taint.analyzeExpressionTaint (toTaintContext context)


{-| Runtime app fields that don't exist at build time.
Note: `action` is NOT in this list because it has the same lifecycle as `data` -
both arrive in the same content.dat response and are only updated on server round-trips.
-}
runtimeAppFields : List String
runtimeAppFields =
    [ "navigation"
    , "pageFormState"
    , "concurrentSubmissions"
    , "submit"
    , "url"
    ]


{-| Check if a module name is a Route module (Route.Something, Route.Blog.Slug\_, etc.)
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
                    , sharedModelParamName = Nothing
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

                    maybeSharedModelParam =
                        arguments
                            |> List.drop 1
                            |> List.head
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
                    , sharedModelParamName = maybeSharedModelParam
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


{-| Unwrap parenthesized expressions recursively.
-}
unwrapParenthesizedExpression : Node Expression -> Node Expression
unwrapParenthesizedExpression node =
    case Node.value node of
        Expression.ParenthesizedExpression inner ->
            unwrapParenthesizedExpression inner

        _ ->
            node


{-| Extract the function node from various View.freeze call forms.
Returns the candidate function node from:

  - Direct application: `View.freeze expr`
  - Right pipe: `expr |> View.freeze`
  - Left pipe: `View.freeze <| expr`

-}
extractFreezeCallNode : Node Expression -> Maybe (Node Expression)
extractFreezeCallNode node =
    case Node.value node of
        Expression.Application (functionNode :: _) ->
            Just (unwrapParenthesizedExpression functionNode)

        Expression.OperatorApplication "|>" _ _ rightExpr ->
            Just (unwrapParenthesizedExpression rightExpr)

        Expression.OperatorApplication "<|" _ leftExpr _ ->
            Just (unwrapParenthesizedExpression leftExpr)

        _ ->
            Nothing


{-| Check if a node is a reference to View.freeze.
-}
isFreezeNode : ModuleContext -> Node Expression -> Bool
isFreezeNode context (Node range expr) =
    case expr of
        Expression.FunctionOrValue _ "freeze" ->
            case ModuleNameLookupTable.moduleNameAt context.lookupTable range of
                Just [ "View" ] ->
                    True

                _ ->
                    False

        _ ->
            False


expressionEnterVisitor : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
expressionEnterVisitor node context =
    -- First, track entering tainted conditionals (if/case)
    context
        |> trackEnteringTaintedConditionals node
        |> checkFreezeCall node


trackEnteringTaintedConditionals : Node Expression -> ModuleContext -> ModuleContext
trackEnteringTaintedConditionals (Node range expr) context =
    case expr of
        Expression.IfBlock cond _ _ ->
            let
                condTaint =
                    analyzeExpressionTaint context cond
            in
            case analyzeExpressionTaint context cond of
                Tainted ->
                    { context | taintedContext = range :: context.taintedContext }

                Pure ->
                    context

        Expression.CaseExpression { expression } ->
            case analyzeExpressionTaint context expression of
                Tainted ->
                    { context | taintedContext = range :: context.taintedContext }

                Pure ->
                    context

        _ ->
            context


checkFreezeCall : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
checkFreezeCall node context =
    case extractFreezeCallNode node of
        Just functionNode ->
            -- Check if this is a call to a frozen view function
            case checkFrozenViewFunctionCall functionNode context of
                Just scopeError ->
                    -- Report scope error and don't enter freeze mode (no point checking taint)
                    ( [ scopeError ], context )

                Nothing ->
                    -- No scope error - check if entering freeze and track taint
                    let
                        isEnteringFreeze =
                            isFreezeNode context functionNode

                        contextWithFreeze =
                            if isEnteringFreeze then
                                { context | freezeCallDepth = context.freezeCallDepth + 1 }

                            else
                                context

                        -- Check if we're entering a View.freeze while inside a tainted conditional
                        -- (only report on first entry to freeze, not on nested freezes)
                        taintedConditionalError =
                            if isEnteringFreeze && context.freezeCallDepth == 0 && not (List.isEmpty context.taintedContext) then
                                -- Just entered freeze while inside tainted conditional
                                [ freezeInTaintedContextError (Node.range functionNode) ]

                            else
                                []
                    in
                    if contextWithFreeze.freezeCallDepth > 0 then
                        checkTaintedReference node contextWithFreeze taintedConditionalError

                    else
                        ( taintedConditionalError, contextWithFreeze )

        Nothing ->
            -- Not a function call form - check taint if in freeze
            if context.freezeCallDepth > 0 then
                checkTaintedReference node context []

            else
                ( [], context )


{-| Check if a function call is to a frozen view function and if the current module is allowed.
Returns Just error if not allowed, Nothing if allowed or not a frozen view function.
-}
checkFrozenViewFunctionCall : Node Expression -> ModuleContext -> Maybe (Error {})
checkFrozenViewFunctionCall functionNode context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ name ->
            case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                Just [ "View" ] ->
                    if List.member name staticFunctionNames && not (isAllowedModule context.moduleName) then
                        Just (frozenViewScopeError (Node.range functionNode) ("View." ++ name))

                    else
                        Nothing

                _ ->
                    Nothing

        _ ->
            Nothing


expressionExitVisitor : Node Expression -> ModuleContext -> ModuleContext
expressionExitVisitor ((Node range expr) as node) context =
    -- Track exiting tainted conditionals (if/case)
    context
        |> trackExitingTaintedConditionals node
        |> checkFreezeCallExit node


trackExitingTaintedConditionals : Node Expression -> ModuleContext -> ModuleContext
trackExitingTaintedConditionals ((Node range expr) as node) context =
    case context.taintedContext of
        [] ->
            context

        taintedRange :: rest ->
            if taintedRange == range then
                { context | taintedContext = rest }

            else
                context


checkFreezeCallExit : Node Expression -> ModuleContext -> ModuleContext
checkFreezeCallExit node context =
    case extractFreezeCallNode node of
        Just functionNode ->
            if isFreezeNode context functionNode then
                { context | freezeCallDepth = max 0 (context.freezeCallDepth - 1) }

            else
                context

        Nothing ->
            context


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
checkTaintedReference : Node Expression -> ModuleContext -> List (Error {}) -> ( List (Error {}), ModuleContext )
checkTaintedReference node context accErrors =
    case Node.value node of
        -- Check for tainted local variable
        Expression.FunctionOrValue [] varName ->
            if context.modelParamName == Just varName || context.sharedModelParamName == Just varName then
                -- model itself is handled by more specific checks (RecordAccess)
                ( accErrors, context )

            else
                case lookupBinding varName context of
                    Just Tainted ->
                        reportErrorIfNew (Node.range node)
                            (taintedValueError (Node.range node) varName)
                            context
                            accErrors

                    _ ->
                        ( accErrors, context )

        -- Check for model.field or taintedVar.field
        Expression.RecordAccess (Node _ (Expression.FunctionOrValue [] varName)) (Node _ fieldName) ->
            case lookupBinding varName context of
                Just Tainted ->
                    reportErrorIfNew (Node.range node)
                        (taintedValueError (Node.range node) varName)
                        context
                        accErrors

                Just Pure ->
                    ( accErrors, context )

                Nothing ->
                    if context.modelParamName == Just varName || context.sharedModelParamName == Just varName then
                        reportErrorIfNew (Node.range node)
                            (modelInFreezeError (Node.range node))
                            context
                            accErrors

                    else if context.appParamName == Just varName && List.member fieldName runtimeAppFields then
                        reportErrorIfNew (Node.range node)
                            (runtimeAppFieldError (Node.range node) fieldName)
                            context
                            accErrors

                    else
                        ( accErrors, context )

        -- Check for cross-module function calls with tainted arguments
        Expression.Application (functionNode :: args) ->
            checkCrossModuleCall functionNode args context accErrors

        -- Pipe operator
        Expression.OperatorApplication "|>" _ leftExpr rightExpr ->
            checkPipeExpression leftExpr rightExpr context accErrors

        -- Case expression
        Expression.CaseExpression caseBlock ->
            checkCaseExpression caseBlock.expression context accErrors

        _ ->
            ( accErrors, context )


{-| Check if a cross-module function call passes tainted values.
-}
checkCrossModuleCall : Node Expression -> List (Node Expression) -> ModuleContext -> List (Error {}) -> ( List (Error {}), ModuleContext )
checkCrossModuleCall functionNode args context accErrors =
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
                                |> (\errorPairs -> collectErrors errorPairs context accErrors)

                        Nothing ->
                            -- Unknown function (external package) - no error
                            ( accErrors, context )

                _ ->
                    ( accErrors, context )

        Nothing ->
            ( accErrors, context )


{-| Check pipe expressions for tainted values.
-}
checkPipeExpression : Node Expression -> Node Expression -> ModuleContext -> List (Error {}) -> ( List (Error {}), ModuleContext )
checkPipeExpression leftExpr rightExpr context accErrors =
    case Node.value rightExpr of
        Expression.RecordAccessFunction fieldName ->
            case Node.value leftExpr of
                Expression.FunctionOrValue [] varName ->
                    if context.modelParamName == Just varName || context.sharedModelParamName == Just varName then
                        reportErrorIfNew (Node.range leftExpr)
                            (accessorOnModelError (Node.range leftExpr))
                            context
                            accErrors

                    else if context.appParamName == Just varName && List.member fieldName runtimeAppFields then
                        reportErrorIfNew (Node.range leftExpr)
                            (accessorOnRuntimeAppFieldError (Node.range leftExpr) fieldName)
                            context
                            accErrors

                    else
                        case lookupBinding varName context of
                            Just Tainted ->
                                reportErrorIfNew (Node.range leftExpr)
                                    (taintedValueError (Node.range leftExpr) varName)
                                    context
                                    accErrors

                            _ ->
                                ( accErrors, context )

                _ ->
                    ( accErrors, context )

        _ ->
            ( accErrors, context )


{-| Check case expressions on tainted values.
-}
checkCaseExpression : Node Expression -> ModuleContext -> List (Error {}) -> ( List (Error {}), ModuleContext )
checkCaseExpression exprNode context accErrors =
    case Node.value exprNode of
        Expression.FunctionOrValue [] varName ->
            if context.modelParamName == Just varName || context.sharedModelParamName == Just varName then
                reportErrorIfNew (Node.range exprNode)
                    (caseOnModelError (Node.range exprNode))
                    context
                    accErrors

            else if context.appParamName == Just varName then
                reportErrorIfNew (Node.range exprNode)
                    (caseOnAppError (Node.range exprNode))
                    context
                    accErrors

            else
                case lookupBinding varName context of
                    Just Tainted ->
                        reportErrorIfNew (Node.range exprNode)
                            (caseOnTaintedValueError (Node.range exprNode) varName)
                            context
                            accErrors

                    _ ->
                        ( accErrors, context )

        _ ->
            ( accErrors, context )



-- ERROR HELPERS


taintedValueError : Range -> String -> Error {}
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


modelInFreezeError : Range -> Error {}
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


runtimeAppFieldError : Range -> String -> Error {}
runtimeAppFieldError range fieldName =
    Rule.error
        { message = "Runtime field `" ++ fieldName ++ "` accessed inside View.freeze"
        , details =
            [ "`app." ++ fieldName ++ "` is runtime-only data that doesn't exist at build time."
            , "Frozen content is rendered once at build time, so runtime fields like `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
            , "To fix this, either:"
            , "1. Move the runtime-dependent content outside of `View.freeze`, or"
            , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.action`, `app.sharedData`, `app.routeParams`, `app.path`"
            ]
        }
        range


accessorOnModelError : Range -> Error {}
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


accessorOnRuntimeAppFieldError : Range -> String -> Error {}
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


caseOnModelError : Range -> Error {}
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


caseOnAppError : Range -> Error {}
caseOnAppError range =
    Rule.error
        { message = "Pattern match on app inside View.freeze"
        , details =
            [ "Using `case app of` inside `View.freeze` accesses the full app record which contains runtime-only fields."
            , "Frozen content is rendered once at build time, and runtime fields like `navigation`, `pageFormState` don't exist yet."
            , "To fix this, either:"
            , "1. Move this content outside of `View.freeze`, or"
            , "2. Access specific build-time fields like `app.data` or `app.routeParams` instead"
            ]
        }
        range


caseOnTaintedValueError : Range -> String -> Error {}
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


crossModuleTaintError : Range -> String -> Error {}
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


frozenViewScopeError : Range -> String -> Error {}
frozenViewScopeError range functionName =
    Rule.error
        { message = "`" ++ functionName ++ "` can only be called from Route modules and Shared.elm"
        , details =
            [ "`" ++ functionName ++ "` currently has no effect outside of Shared.elm and your Route modules (files in your `app/Route/` directory)."
            , "To fix this, either:"
            , "1. Use `" ++ functionName ++ "` in a Route Module (it could simply be `View.freeze (myHelperFunction app.data.user)`)"
            , "2. Remove this invalid use of `" ++ functionName ++ "`"
            ]
        }
        range


freezeInTaintedContextError : Range -> Error {}
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
