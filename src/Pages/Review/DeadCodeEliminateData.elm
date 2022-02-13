module Pages.Review.DeadCodeEliminateData exposing (rule)

import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node)
import Review.Fix
import Review.Rule as Rule exposing (Direction, Error, Rule)


rule : Rule
rule =
    Rule.newModuleRuleSchema "Pages.Review.DeadCodeEliminateData"
        { moduleName = []
        , isPageModule = False
        }
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.withDeclarationEnterVisitor declarationVisitor
        |> Rule.fromModuleRuleSchema


declarationVisitor : Node Declaration -> context -> ( List (Error {}), context )
declarationVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration { documentation, declaration } ->
            let
                functionName : String
                functionName =
                    Node.value declaration |> .name |> Node.value
            in
            case Node.value declaration of
                { name, expression } ->
                    case ( Node.value name, Node.value expression ) of
                        ( "template", Expression.RecordExpr setters ) ->
                            let
                                dataFieldValue =
                                    setters
                                        |> List.filterMap
                                            (\recordSetter ->
                                                case Node.value recordSetter of
                                                    ( keyNode, valueNode ) ->
                                                        if Node.value keyNode == "data" then
                                                            if isAlreadyApplied (Node.value valueNode) then
                                                                Nothing

                                                            else
                                                                recordSetter |> Just

                                                        else
                                                            Nothing
                                            )
                                        |> List.head
                            in
                            dataFieldValue
                                |> Maybe.map
                                    (\dataValue ->
                                        ( [ Rule.errorWithFix
                                                { message = "Codemod"
                                                , details = [ "" ]
                                                }
                                                (Node.range dataValue)
                                                [ Review.Fix.replaceRangeBy (Node.range dataValue) "data = DataSource.fail \"\"\n    "
                                                ]
                                          ]
                                        , context
                                        )
                                    )
                                |> Maybe.withDefault
                                    ( [], context )

                        _ ->
                            ( [], context )

        _ ->
            ( [], context )


expressionVisitor : Node Expression -> context -> ( List (Error {}), context )
expressionVisitor node context =
    case Node.value node of
        Expression.Application applicationExpressions ->
            case applicationExpressions |> List.map Node.value of
                [ Expression.FunctionOrValue [ "Page" ] pageBuilderName, Expression.RecordExpr fields ] ->
                    let
                        dataFieldValue =
                            fields
                                |> List.filterMap
                                    (\recordSetter ->
                                        case Node.value recordSetter of
                                            ( keyNode, valueNode ) ->
                                                if Node.value keyNode == "data" then
                                                    if isAlreadyApplied (Node.value valueNode) then
                                                        Nothing

                                                    else
                                                        recordSetter |> Just

                                                else
                                                    Nothing
                                    )
                                |> List.head
                    in
                    dataFieldValue
                        |> Maybe.map
                            (\dataValue ->
                                ( [ Rule.errorWithFix
                                        { message = "Codemod"
                                        , details = [ "" ]
                                        }
                                        (Node.range dataValue)
                                        [ if pageBuilderName == "preRender" then
                                            Review.Fix.replaceRangeBy (Node.range dataValue) "data = \\_ -> DataSource.fail \"\""

                                          else
                                            Review.Fix.replaceRangeBy (Node.range dataValue) "data = DataSource.fail \"\"\n       "
                                        ]
                                  ]
                                , context
                                )
                            )
                        |> Maybe.withDefault
                            ( [], context )

                rest ->
                    ( [], context )

        _ ->
            ( [], context )


isAlreadyApplied : Expression -> Bool
isAlreadyApplied expression =
    case expression of
        Expression.LambdaExpression info ->
            case Node.value info.expression of
                Expression.Application applicationNodes ->
                    case applicationNodes |> List.map Node.value of
                        (Expression.FunctionOrValue [ "DataSource" ] "fail") :: rest ->
                            True

                        _ ->
                            False

                _ ->
                    False

        Expression.Application applicationNodes ->
            case applicationNodes |> List.map Node.value of
                (Expression.FunctionOrValue [ "DataSource" ] "fail") :: rest ->
                    True

                _ ->
                    False

        _ ->
            False
