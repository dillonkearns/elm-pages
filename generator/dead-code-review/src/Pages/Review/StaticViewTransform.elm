module Pages.Review.StaticViewTransform exposing (rule)

{-| This rule transforms static region render calls into adopt calls in the client
bundle. This enables dead-code elimination of the static rendering dependencies
(markdown parsers, syntax highlighters, etc.) while preserving the pre-rendered
HTML for adoption by the virtual-dom.

Transforms:

    -- User's View.renderStatic (new API):
    View.renderStatic "id" (staticContent ())
    -- becomes:
    View.embedStatic (View.htmlToStatic (View.Static.adopt "id"))

    -- Direct View.Static.render (legacy):
    View.Static.render "id" content
    -- becomes:
    View.Static.adopt "id"

The key insight is that by replacing the entire `View.renderStatic` call, we
prevent `staticContent ()` from being called, allowing DCE to eliminate it.

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
                -- Two-argument application: fn arg1 arg2
                functionNode :: idArg :: contentArg :: [] ->
                    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                        -- View.renderStatic "id" expr → View.embedStatic (View.Static.adopt "id")
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "renderStatic" ->
                                    let
                                        replacement =
                                            renderStaticAdoptCall context idArg
                                    in
                                    ( [ Rule.errorWithFix
                                            { message = "Static region codemod: transform renderStatic to adopt"
                                            , details = [ "Transforms View.renderStatic to View.embedStatic (View.Static.adopt ...) for client-side adoption and DCE" ]
                                            }
                                            (Node.range node)
                                            [ Review.Fix.replaceRangeBy (Node.range node) replacement
                                            ]
                                      ]
                                    , context
                                    )

                                _ ->
                                    ( [], context )

                        -- View.Static.render "id" content → View.Static.adopt "id" (legacy)
                        Just [ "View", "Static" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "render" ->
                                    let
                                        adoptCall =
                                            viewStaticAdoptCall context idArg
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

                                _ ->
                                    ( [], context )

                        _ ->
                            ( [], context )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )


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
