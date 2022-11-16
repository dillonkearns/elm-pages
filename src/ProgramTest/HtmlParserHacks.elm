module ProgramTest.HtmlParserHacks exposing (parse, trimText)

import Html.Parser
import Parser
import ProgramTest.StringLines as StringLines


parse : String -> Result (List Parser.DeadEnd) (List Html.Parser.Node)
parse input =
    case Html.Parser.run input of
        Ok nodes ->
            Ok nodes

        Err errs ->
            case fixError errs input of
                Nothing ->
                    Err errs

                Just nodes ->
                    Ok nodes


fixError : List Parser.DeadEnd -> String -> Maybe (List Html.Parser.Node)
fixError errs input =
    case errs of
        [] ->
            Nothing

        { row, col, problem } :: rest ->
            case problem of
                Parser.UnexpectedChar ->
                    case StringLines.charAt row (col - 1) input of
                        Just "<" ->
                            parse (StringLines.replaceAt row (col - 1) "&lt;" input)
                                |> Result.toMaybe

                        _ ->
                            fixError rest input

                _ ->
                    fixError rest input


trimText : Html.Parser.Node -> Html.Parser.Node
trimText node =
    case node of
        Html.Parser.Text string ->
            Html.Parser.Text (String.trim string)

        Html.Parser.Element string list nodes ->
            Html.Parser.Element string
                list
                (List.map trimText nodes
                    |> List.filter ((/=) (Html.Parser.Text ""))
                )

        Html.Parser.Comment string ->
            Html.Parser.Comment string
