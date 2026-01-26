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

import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , moduleName : ModuleName
    , inFreezeCall : Bool
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
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


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


{-| Check if the expression is a reference to `model` and we're inside a freeze call.
-}
checkModelReference : Node Expression -> Context -> List (Error {})
checkModelReference node context =
    case Node.value node of
        Expression.FunctionOrValue [] "model" ->
            [ modelInFreezeError (Node.range node) ]

        Expression.RecordAccess innerExpr _ ->
            -- Check for model.field
            case Node.value innerExpr of
                Expression.FunctionOrValue [] "model" ->
                    [ modelInFreezeError (Node.range node) ]

                _ ->
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
