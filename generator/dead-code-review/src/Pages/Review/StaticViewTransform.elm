module Pages.Review.StaticViewTransform exposing (rule)

{-| This rule transforms `View.Static.render` calls into `View.Static.adopt` calls
in the client bundle. This enables dead-code elimination of the static rendering
dependencies (markdown parsers, syntax highlighters, etc.) while preserving the
pre-rendered HTML for adoption by the virtual-dom.

Transform:

    View.Static.render "markdown" fallbackHtml content
    -- becomes:
    View.Static.adopt "markdown" fallbackHtml

-}

import Dict exposing (Dict)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.Range exposing (Range)
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , viewStaticAlias : Maybe ModuleName
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
            }
        )
        |> Rule.withModuleNameLookupTable


importVisitor : Node Import -> Context -> ( List (Rule.Error {}), Context )
importVisitor node context =
    let
        import_ =
            Node.value node
    in
    if import_.moduleName |> Node.value |> (==) [ "View", "Static" ] then
        ( []
        , { context
            | viewStaticAlias =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "View", "Static" ]
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
                functionNode :: idArg :: fallbackArg :: contentArg :: [] ->
                    -- Check if this is View.Static.render
                    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                        Just [ "View", "Static" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "render" ->
                                    -- This is View.Static.render, transform it
                                    let
                                        adoptCall =
                                            renderAdoptCall context idArg fallbackArg
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


{-| Generate the View.Static.adopt call string
-}
renderAdoptCall : Context -> Node Expression -> Node Expression -> String
renderAdoptCall context idArg fallbackArg =
    let
        modulePrefix =
            context.viewStaticAlias
                |> Maybe.withDefault [ "View", "Static" ]
                |> String.join "."

        idStr =
            expressionToString idArg

        fallbackStr =
            expressionToString fallbackArg
    in
    modulePrefix ++ ".adopt " ++ idStr ++ " " ++ fallbackStr


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
