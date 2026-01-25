module Pages.Review.StaticRegionScope exposing (rule)

{-| This rule ensures that static region functions are only called from Route modules.

Static regions (View.static, View.staticView, View.staticBackendTask, View.Static.view, etc.)
are transformed by elm-review during the client-side build. This transformation only works
for Route modules. Calling these functions from other modules (like Shared.elm or helper
modules) will NOT enable DCE - the heavy dependencies will still be in the client bundle.

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
    }


{-| Reports calls to static region functions outside of Route modules.

    config =
        [ Pages.Review.StaticRegionScope.rule
        ]


## Fail

    -- In Shared.elm or any non-Route module:
    view =
        View.static (heavyContent ())  -- ERROR


## Success

    -- In Route/Index.elm or any Route.* module:
    view =
        View.static (heavyContent ())  -- OK


## Why This Matters

Static region transformations only work in Route modules. The elm-review codemod that
enables dead-code elimination runs on Route modules and transforms `View.static` calls
to `View.adopt` calls. If you call `View.static` in a non-Route module:

1.  The transformation won't happen
2.  The heavy rendering code will be in the client bundle
3.  You won't see any error - just unexpectedly large bundle sizes

This rule prevents that silent failure by erroring at build time.

-}
rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.StaticRegionScope" initialContext
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.fromModuleRuleSchema


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable moduleName () ->
            { lookupTable = lookupTable
            , moduleName = moduleName
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


{-| Static region functions that should only be called from Route modules.
-}
staticFunctionNames : List String
staticFunctionNames =
    [ "static"
    , "staticView"
    , "staticBackendTask"
    , "renderStatic"
    ]


{-| Static functions in View.Static module
-}
viewStaticFunctionNames : List String
viewStaticFunctionNames =
    [ "static"
    , "view"
    , "backendTask"
    , "render"
    ]


expressionVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionVisitor node context =
    if isRouteModule context.moduleName then
        -- Route modules can use static regions freely
        ( [], context )

    else
        case Node.value node of
            Expression.Application (functionNode :: _) ->
                case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                    Just [ "View" ] ->
                        checkViewFunction functionNode context

                    Just [ "View", "Static" ] ->
                        checkViewStaticFunction functionNode context

                    _ ->
                        ( [], context )

            _ ->
                ( [], context )


checkViewFunction : Node Expression -> Context -> ( List (Error {}), Context )
checkViewFunction functionNode context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ name ->
            if List.member name staticFunctionNames then
                ( [ staticRegionScopeError (Node.range functionNode) ("View." ++ name) ]
                , context
                )

            else
                ( [], context )

        _ ->
            ( [], context )


checkViewStaticFunction : Node Expression -> Context -> ( List (Error {}), Context )
checkViewStaticFunction functionNode context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ name ->
            if List.member name viewStaticFunctionNames then
                ( [ staticRegionScopeError (Node.range functionNode) ("View.Static." ++ name) ]
                , context
                )

            else
                ( [], context )

        _ ->
            ( [], context )


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
