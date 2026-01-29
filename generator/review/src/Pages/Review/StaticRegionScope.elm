module Pages.Review.StaticRegionScope exposing (rule)

{-| This rule ensures that static region functions are only called from Route modules
and that model is not referenced inside freeze calls.

Static regions (View.freeze, View.Static.static) are transformed by elm-review during
the client-side build. This transformation only works for Route modules. Calling these
functions from other modules (like Shared.elm or helper modules) will NOT enable DCE -
the heavy dependencies will still be in the client bundle.

Additionally, this rule checks that `model` is not referenced inside `View.freeze` calls.
Since frozen content is rendered at build time (when model doesn't exist), referencing
model would cause the content to be stale or cause runtime errors.

@docs rule

-}

import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , moduleName : ModuleName
    , inFreezeCall : Bool
    , appParamName : Maybe String
    }


{-| Reports:

1.  Calls to static region functions outside of Route modules
2.  References to `model` inside `View.freeze` calls

    config =
        [ Pages.Review.StaticRegionScope.rule
        ]


## Fail

    -- In Shared.elm or any non-Route module:
    view =
        View.freeze (heavyContent ())  -- ERROR: outside Route module

    -- In any module, inside freeze:
    view app shared model =
        { body =
            [ View.freeze (div [] [ text model.name ]) -- ERROR: model in freeze
            ]
        }


## Success

    -- In Route/Index.elm or any Route.* module:
    view app shared model =
        { body =
            [ View.freeze (div [] [ text app.data.content ])  -- OK
            , div [] [ text model.name ]  -- OK, outside freeze
            ]
        }


## Why This Matters

**Static region scope:**
Static region transformations only work in Route modules. The elm-review codemod that
enables dead-code elimination runs on Route modules and transforms `View.freeze` calls
to `View.adopt` calls. If you call `View.freeze` in a non-Route module:

1.  The transformation won't happen
2.  The heavy rendering code will be in the client bundle
3.  You won't see any error - just unexpectedly large bundle sizes

**Model references in freeze:**
Frozen content is rendered at build time when there is no model state. If you reference
`model` inside a `View.freeze` call:

1.  The content would be frozen with stale/initial model data
2.  Changes to model wouldn't update the frozen content
3.  This is almost certainly a bug in your code

-}
rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.StaticRegionScope" initialContext
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.fromModuleRuleSchema


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable moduleName () ->
            { lookupTable = lookupTable
            , moduleName = moduleName
            , inFreezeCall = False
            , appParamName = Nothing
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


{-| Runtime app fields that don't exist at build time.
These should not be accessed inside View.freeze.
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


{-| Build-time app fields that are safe to use in View.freeze.
-}
buildTimeAppFields : List String
buildTimeAppFields =
    [ "data"
    , "sharedData"
    , "routeParams"
    , "path"
    ]


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
            in
            if functionName == "view" then
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
                ( [], { context | appParamName = maybeAppParam } )

            else
                ( [], context )

        _ ->
            ( [], context )


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


{-| Check if a module name is a Route module (Route.Something, Route.Blog.Slug_, etc.)
-}
isRouteModule : ModuleName -> Bool
isRouteModule moduleName =
    case moduleName of
        "Route" :: _ :: _ ->
            True

        _ ->
            False


{-| Check if a module name is allowed to use static region functions.

This includes Route modules and the View module (which provides helper functions
that are ultimately called from Route modules).

-}
isAllowedModule : ModuleName -> Bool
isAllowedModule moduleName =
    isRouteModule moduleName || moduleName == [ "View" ]


{-| Static region functions that should only be called from Route modules.
-}
staticFunctionNames : List String
staticFunctionNames =
    [ "freeze"
    ]


{-| Static functions in View.Static module
-}
viewStaticFunctionNames : List String
viewStaticFunctionNames =
    [ "static"
    , "view"
    ]


expressionEnterVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionEnterVisitor node context =
    let
        -- Check for entering a freeze call
        ( newInFreezeCall, freezeErrors ) =
            case Node.value node of
                Expression.Application (functionNode :: _) ->
                    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "freeze" ->
                                    ( True, [] )

                                _ ->
                                    ( context.inFreezeCall, [] )

                        _ ->
                            ( context.inFreezeCall, [] )

                _ ->
                    ( context.inFreezeCall, [] )

        contextWithFreeze =
            { context | inFreezeCall = newInFreezeCall }

        -- Check for model reference inside freeze
        modelErrors =
            if contextWithFreeze.inFreezeCall then
                checkModelReference node contextWithFreeze

            else
                []

        -- Check for scope errors (static functions outside Route modules)
        scopeErrors =
            if isAllowedModule context.moduleName then
                []

            else
                checkScopeErrors node context
    in
    ( freezeErrors ++ modelErrors ++ scopeErrors, contextWithFreeze )


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


{-| Check if the expression is a reference to `model`, a runtime app field,
or uses patterns like `model |> .field` inside a freeze call.

Note: We need to be careful to avoid duplicate errors. For example,
`model.field` should only report one error (for the RecordAccess),
not two (one for FunctionOrValue "model" and one for RecordAccess).
The AST visitor will visit both the outer RecordAccess and inner FunctionOrValue.
We handle this by:
- Only catching direct `model` references when they're standalone
- Catching `model.field` at the RecordAccess level
-}
checkModelReference : Node Expression -> Context -> List (Error {})
checkModelReference node context =
    case Node.value node of
        -- model.field - report error at the RecordAccess level
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] "model" ->
                    [ modelInFreezeError (Node.range node) ]

                -- Check for app.runtimeField (like app.action, app.navigation)
                Expression.FunctionOrValue [] varName ->
                    if context.appParamName == Just varName && List.member fieldName runtimeAppFields then
                        [ runtimeAppFieldInFreezeError (Node.range node) fieldName ]

                    else
                        []

                _ ->
                    []

        -- Pipe operator: model |> .field or app |> .action
        Expression.OperatorApplication "|>" _ leftExpr rightExpr ->
            checkPipeAccessor leftExpr rightExpr context

        -- Case expression: case model of {...}
        Expression.CaseExpression caseBlock ->
            checkCaseExpression caseBlock.expression context

        _ ->
            []


{-| Check for accessor patterns in pipe expressions: `model |> .field`, `app |> .action`

NOTE: For `app |> .action`, we check if the field is a runtime-only field.
For `app |> .data`, we allow it because data is available at build time.
-}
checkPipeAccessor : Node Expression -> Node Expression -> Context -> List (Error {})
checkPipeAccessor leftExpr rightExpr context =
    case Node.value rightExpr of
        Expression.RecordAccessFunction fieldName ->
            case Node.value leftExpr of
                -- model |> .field
                Expression.FunctionOrValue [] "model" ->
                    [ accessorOnModelInFreezeError (Node.range leftExpr) ]

                -- app |> .action (runtime field)
                Expression.FunctionOrValue [] varName ->
                    -- Check if varName matches app param AND field is a runtime field
                    case context.appParamName of
                        Just appName ->
                            if varName == appName && List.member fieldName runtimeAppFields then
                                [ accessorOnAppRuntimeFieldInFreezeError (Node.range leftExpr) fieldName ]

                            else
                                []

                        Nothing ->
                            []

                _ ->
                    []

        _ ->
            []


{-| Check for case expressions on model or app: `case model of {...}`
-}
checkCaseExpression : Node Expression -> Context -> List (Error {})
checkCaseExpression exprNode context =
    case Node.value exprNode of
        Expression.FunctionOrValue [] "model" ->
            [ caseOnModelInFreezeError (Node.range exprNode) ]

        -- app (without field access) - accessing the whole app record in a case
        Expression.FunctionOrValue [] varName ->
            if context.appParamName == Just varName then
                [ caseOnAppInFreezeError (Node.range exprNode) ]

            else
                []

        _ ->
            []


{-| Check for static region function calls outside of allowed modules.
-}
checkScopeErrors : Node Expression -> Context -> List (Error {})
checkScopeErrors node context =
    case Node.value node of
        Expression.Application (functionNode :: _) ->
            case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                Just [ "View" ] ->
                    checkViewFunction functionNode

                Just [ "View", "Static" ] ->
                    checkViewStaticFunction functionNode

                _ ->
                    []

        _ ->
            []


checkViewFunction : Node Expression -> List (Error {})
checkViewFunction functionNode =
    case Node.value functionNode of
        Expression.FunctionOrValue _ name ->
            if List.member name staticFunctionNames then
                [ staticRegionScopeError (Node.range functionNode) ("View." ++ name) ]

            else
                []

        _ ->
            []


checkViewStaticFunction : Node Expression -> List (Error {})
checkViewStaticFunction functionNode =
    case Node.value functionNode of
        Expression.FunctionOrValue _ name ->
            if List.member name viewStaticFunctionNames then
                [ staticRegionScopeError (Node.range functionNode) ("View.Static." ++ name) ]

            else
                []

        _ ->
            []


staticRegionScopeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
staticRegionScopeError range functionName =
    Rule.error
        { message = "Static region function called outside Route module"
        , details =
            [ "`" ++ functionName ++ "` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
            , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
            , "To fix this, either:"
            , "1. Move this code to a Route module, or"
            , "2. Pass the static content as a parameter from the Route module"
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


runtimeAppFieldInFreezeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
runtimeAppFieldInFreezeError range fieldName =
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


accessorOnModelInFreezeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
accessorOnModelInFreezeError range =
    Rule.error
        { message = "Accessor on model inside View.freeze"
        , details =
            [ "Frozen content is rendered at build time when no model state exists."
            , "Using `model |> .field` inside `View.freeze` accesses model data that won't exist at build time."
            , "To fix this, move the model-dependent content outside of `View.freeze`."
            ]
        }
        range


accessorOnAppRuntimeFieldInFreezeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> String -> Error {}
accessorOnAppRuntimeFieldInFreezeError range fieldName =
    Rule.error
        { message = "Accessor on runtime app field inside View.freeze"
        , details =
            [ "`app |> ." ++ fieldName ++ "` accesses runtime-only data that doesn't exist at build time."
            , "Frozen content is rendered once at build time, so runtime fields are not available."
            , "To fix this, move this content outside of `View.freeze`."
            ]
        }
        range


caseOnModelInFreezeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
caseOnModelInFreezeError range =
    Rule.error
        { message = "Pattern match on model inside View.freeze"
        , details =
            [ "Frozen content is rendered at build time when no model state exists."
            , "Using `case model of` inside `View.freeze` depends on model data that won't exist at build time."
            , "To fix this, move the model-dependent content outside of `View.freeze`."
            ]
        }
        range


caseOnAppInFreezeError : { start : { row : Int, column : Int }, end : { row : Int, column : Int } } -> Error {}
caseOnAppInFreezeError range =
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
