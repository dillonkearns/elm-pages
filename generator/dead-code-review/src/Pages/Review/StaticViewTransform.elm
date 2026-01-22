module Pages.Review.StaticViewTransform exposing (rule)

{-| This rule transforms static region render calls into adopt calls in the client
bundle. This enables dead-code elimination of the static rendering dependencies
(markdown parsers, syntax highlighters, etc.) while preserving the pre-rendered
HTML for adoption by the virtual-dom.

Transforms:

    -- View.static (auto-ID):
    View.static (heavyRender data)
    -- becomes:
    View.embedStatic (View.adopt "0")  -- ID assigned based on source order

    -- View.staticView with StaticOnlyData (auto-ID):
    View.staticView app.staticData (\data -> heavyRender data)
    -- becomes:
    View.embedStatic (View.adopt "0")  -- Both data and render fn eliminated

    -- View.Static.view with StaticOnlyData (auto-ID):
    View.Static.view staticData (\data -> heavyRender data)
    -- becomes:
    View.Static.adopt "0"

    -- View.staticBackendTask (static-only data):
    View.staticBackendTask (parseMarkdown "content.md")
    -- becomes:
    BackendTask.fail (FatalError.fromString "static only data")

    -- View.Static.backendTask (static-only data):
    View.Static.backendTask (parseMarkdown "content.md")
    -- becomes:
    BackendTask.fail (FatalError.fromString "static only data")

    -- View.renderStatic (explicit ID):
    View.renderStatic "id" (staticContent ())
    -- becomes:
    View.embedStatic (View.adopt "id")

    -- Direct View.Static.render (legacy):
    View.Static.render "id" content
    -- becomes:
    View.Static.adopt "id"

The key insight is that by replacing the entire call, we prevent the static
content expression from being called, allowing DCE to eliminate it.

-}

import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node)
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , viewStaticAlias : Maybe ModuleName
    , viewAlias : Maybe ModuleName
    , staticIndex : Int
    }


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.StaticViewTransform" initialContext
        |> Rule.providesFixesForModuleRule
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.withImportVisitor importVisitor
        |> Rule.fromModuleRuleSchema


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable () ->
            { lookupTable = lookupTable
            , viewStaticAlias = Nothing
            , viewAlias = Nothing
            , staticIndex = 0
            }
        )
        |> Rule.withModuleNameLookupTable


importVisitor : Node Import -> Context -> ( List (Rule.Error {}), Context )
importVisitor node context =
    let
        import_ =
            Node.value node

        moduleName =
            Node.value import_.moduleName
    in
    if moduleName == [ "View", "Static" ] then
        ( []
        , { context
            | viewStaticAlias =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "View", "Static" ]
                    |> Just
          }
        )

    else if moduleName == [ "View" ] then
        ( []
        , { context
            | viewAlias =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "View" ]
                    |> Just
          }
        )

    else
        ( [], context )


expressionVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        Expression.Application applicationExpressions ->
            case applicationExpressions of
                -- Single-argument application: View.static expr, View.staticBackendTask expr, etc.
                functionNode :: contentArg :: [] ->
                    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "static" ->
                                    let
                                        replacement =
                                            viewStaticAutoIdCall context
                                    in
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform View.static to adopt"
                                            , details = [ "Transforms View.static to View.embedStatic (View.adopt \"index\") for client-side adoption and DCE" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) replacement
                                            ]
                                      ]
                                    , { context | staticIndex = context.staticIndex + 1 }
                                    )

                                Expression.FunctionOrValue _ "staticBackendTask" ->
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform View.staticBackendTask to BackendTask.fail"
                                            , details = [ "Transforms View.staticBackendTask to BackendTask.fail for DCE of static-only data" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) backendTaskFailCall
                                            ]
                                      ]
                                    , context
                                    )

                                _ ->
                                    ( [], context )

                        Just [ "View", "Static" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "static" ->
                                    let
                                        replacement =
                                            viewStaticModuleAutoIdCall context
                                    in
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform View.Static.static to adopt"
                                            , details = [ "Transforms View.Static.static to View.Static.adopt \"index\" for client-side adoption and DCE" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) replacement
                                            ]
                                      ]
                                    , { context | staticIndex = context.staticIndex + 1 }
                                    )

                                Expression.FunctionOrValue _ "backendTask" ->
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform View.Static.backendTask to BackendTask.fail"
                                            , details = [ "Transforms View.Static.backendTask to BackendTask.fail for DCE of static-only data" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) backendTaskFailCall
                                            ]
                                      ]
                                    , context
                                    )

                                _ ->
                                    ( [], context )

                        _ ->
                            ( [], context )

                -- Two-argument application: fn arg1 arg2
                functionNode :: firstArg :: secondArg :: [] ->
                    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                        -- View.renderStatic "id" expr → View.embedStatic (View.adopt "id")
                        -- View.staticView staticData renderFn → View.embedStatic (View.adopt "index")
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "renderStatic" ->
                                    let
                                        replacement =
                                            renderStaticAdoptCall context firstArg
                                    in
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform renderStatic to adopt"
                                            , details = [ "Transforms View.renderStatic to View.embedStatic (View.adopt ...) for client-side adoption and DCE" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) replacement
                                            ]
                                      ]
                                    , context
                                    )

                                Expression.FunctionOrValue _ "staticView" ->
                                    let
                                        replacement =
                                            viewStaticAutoIdCall context
                                    in
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform View.staticView to adopt"
                                            , details = [ "Transforms View.staticView to View.embedStatic (View.adopt \"index\") for client-side adoption and DCE" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) replacement
                                            ]
                                      ]
                                    , { context | staticIndex = context.staticIndex + 1 }
                                    )

                                _ ->
                                    ( [], context )

                        -- View.Static.render "id" content → View.Static.adopt "id" (legacy)
                        -- View.Static.view staticData renderFn → View.Static.adopt "index"
                        Just [ "View", "Static" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "render" ->
                                    let
                                        adoptCall =
                                            viewStaticAdoptCall context firstArg
                                    in
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform render to adopt"
                                            , details = [ "Transforms View.Static.render to View.Static.adopt for client-side adoption" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) adoptCall
                                            ]
                                      ]
                                    , context
                                    )

                                Expression.FunctionOrValue _ "view" ->
                                    let
                                        replacement =
                                            viewStaticModuleAutoIdCall context
                                    in
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform View.Static.view to adopt"
                                            , details = [ "Transforms View.Static.view to View.Static.adopt \"index\" for client-side adoption and DCE" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) replacement
                                            ]
                                      ]
                                    , { context | staticIndex = context.staticIndex + 1 }
                                    )

                                _ ->
                                    ( [], context )

                        _ ->
                            ( [], context )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )


{-| Generate BackendTask.fail for static-only BackendTask transforms
-}
backendTaskFailCall : String
backendTaskFailCall =
    "BackendTask.fail (FatalError.fromString \"static only data\")"


{-| Generate View.embedStatic (View.adopt "index") for View.static with auto-ID
-}
viewStaticAutoIdCall : Context -> String
viewStaticAutoIdCall context =
    let
        viewPrefix =
            context.viewAlias
                |> Maybe.withDefault [ "View" ]
                |> String.join "."

        idStr =
            "\"" ++ String.fromInt context.staticIndex ++ "\""
    in
    viewPrefix ++ ".embedStatic (" ++ viewPrefix ++ ".adopt " ++ idStr ++ ")"


{-| Generate View.Static.adopt "index" for View.Static.static with auto-ID
-}
viewStaticModuleAutoIdCall : Context -> String
viewStaticModuleAutoIdCall context =
    let
        modulePrefix =
            context.viewStaticAlias
                |> Maybe.withDefault [ "View", "Static" ]
                |> String.join "."

        idStr =
            "\"" ++ String.fromInt context.staticIndex ++ "\""
    in
    modulePrefix ++ ".adopt " ++ idStr


{-| Generate View.embedStatic (View.adopt "id") for View.renderStatic

The View module provides adopt which wraps View.Static.adopt and converts
to Html.Styled, so we can use it directly with embedStatic.

-}
renderStaticAdoptCall : Context -> Node Expression -> String
renderStaticAdoptCall context idArg =
    let
        viewPrefix =
            context.viewAlias
                |> Maybe.withDefault [ "View" ]
                |> String.join "."

        idStr =
            expressionToString idArg
    in
    viewPrefix ++ ".embedStatic (" ++ viewPrefix ++ ".adopt " ++ idStr ++ ")"


{-| Generate View.Static.adopt "id" for legacy View.Static.render
-}
viewStaticAdoptCall : Context -> Node Expression -> String
viewStaticAdoptCall context idArg =
    let
        modulePrefix =
            context.viewStaticAlias
                |> Maybe.withDefault [ "View", "Static" ]
                |> String.join "."

        idStr =
            expressionToString idArg
    in
    modulePrefix ++ ".adopt " ++ idStr


{-| Convert an expression node back to a string representation.
This is a simplified version - handles common cases.
-}
expressionToString : Node Expression -> String
expressionToString node =
    case Node.value node of
        Expression.Literal str ->
            "\"" ++ str ++ "\""

        Expression.FunctionOrValue moduleName name ->
            case moduleName of
                [] ->
                    name

                _ ->
                    String.join "." moduleName ++ "." ++ name

        Expression.RecordAccess expr field ->
            expressionToString expr ++ "." ++ Node.value field

        Expression.Application exprs ->
            "(" ++ (List.map expressionToString exprs |> String.join " ") ++ ")"

        Expression.ParenthesizedExpression expr ->
            "(" ++ expressionToString expr ++ ")"

        _ ->
            -- For complex expressions, wrap in parens to be safe
            -- This is a fallback - ideally we'd handle more cases
            "(???)"
