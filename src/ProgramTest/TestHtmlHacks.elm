module ProgramTest.TestHtmlHacks exposing (getPassingSelectors, parseFailureReport, parseFailureReportWithoutHtml, parseSimulateFailure, renderHtml)

import Html.Parser
import Parser
import Parser.Extra
import ProgramTest.HtmlHighlighter as HtmlHighlighter
import ProgramTest.HtmlRenderer as HtmlRenderer
import ProgramTest.TestHtmlParser as TestHtmlParser exposing (Assertion(..), FailureReport(..))
import Test.Html.Query as Query
import Test.Html.Selector as Selector exposing (Selector)
import Test.Runner


pleaseReport description =
    "PLEASE REPORT THIS AT <https://github.com/avh4/elm-program-test/issues>: " ++ description


renderHtml : (String -> String) -> (String -> List Html.Parser.Attribute -> List Html.Parser.Node -> Bool) -> Query.Single any -> String
renderHtml colorHidden highlightPredicate single =
    case forceFailureReport [] single of
        Ok (QueryFailure node _ _) ->
            let
                tryHighlight =
                    HtmlHighlighter.highlight highlightPredicate
                        node

                finalHighlighted =
                    if HtmlHighlighter.isNonHiddenElement tryHighlight then
                        tryHighlight

                    else
                        HtmlHighlighter.highlight (\_ _ _ -> True)
                            node
            in
            "▼ Query.fromHtml\n\n"
                ++ HtmlRenderer.render colorHidden 4 [ finalHighlighted ]

        Ok (EventFailure name _) ->
            pleaseReport ("renderHtml: unexpected EventFailure: \"" ++ name ++ "\"")

        Err err ->
            pleaseReport ("renderHtml: couldn't parse failure report: " ++ err)


getPassingSelectors : List Selector -> Query.Single msg -> List String
getPassingSelectors selectors single =
    case forceFailureReportWithoutHtml selectors single of
        Ok (QueryFailure _ _ (Has _ results)) ->
            case List.reverse results of
                (Ok _) :: _ ->
                    [ pleaseReport "getPassingSelectors: forced selector didn't fail" ]

                _ ->
                    List.filterMap Result.toMaybe results

        Ok (EventFailure name _) ->
            [ pleaseReport ("getPassingSelectors: got unexpected EventFailure \"" ++ name ++ "\"") ]

        Err err ->
            [ pleaseReport ("getPassingSelectors: couldn't parse failure report: " ++ err) ]


forceFailureReport : List Selector -> Query.Single any -> Result String (FailureReport Html.Parser.Node)
forceFailureReport selectors =
    forceFailureReport_ parseFailureReport selectors "ProgramTest.TestHtmlHacks is trying to force a failure to collect the error message %%"


forceFailureReportWithoutHtml : List Selector -> Query.Single any -> Result String (FailureReport ())
forceFailureReportWithoutHtml selectors =
    forceFailureReport_ parseFailureReportWithoutHtml selectors "ProgramTest.TestHtmlHacks is trying to force a failure to collect the error message %%"


forceFailureReport_ : (String -> result) -> List Selector -> String -> Query.Single any -> result
forceFailureReport_ parseFailure selectors unique single =
    case
        single
            |> Query.has (selectors ++ [ Selector.text unique ])
            |> Test.Runner.getFailureReason
    of
        Nothing ->
            -- We expect the fake query to fail -- if it doesn't for some reason, just try recursing with a different fake matching string until it does fail
            forceFailureReport_ parseFailure selectors (unique ++ "_") single

        Just reason ->
            parseFailure reason.description


parseFailureReport : String -> Result String (FailureReport Html.Parser.Node)
parseFailureReport string =
    Parser.run TestHtmlParser.parser string
        |> Result.mapError Parser.Extra.deadEndsToString


parseFailureReportWithoutHtml : String -> Result String (FailureReport ())
parseFailureReportWithoutHtml string =
    Parser.run TestHtmlParser.parserWithoutHtml string
        |> Result.mapError Parser.Extra.deadEndsToString


partitionSections_ : List String -> List (List String) -> List String -> List (List String)
partitionSections_ accLines accSections remaining =
    case remaining of
        [] ->
            case List.reverse (List.reverse accLines :: accSections) of
                [] :: rest ->
                    rest

                all ->
                    all

        next :: rest ->
            if String.startsWith "▼ " next then
                partitionSections_ [ next ] (List.reverse accLines :: accSections) rest

            else
                partitionSections_ (next :: accLines) accSections rest


parseSimulateFailure : String -> String
parseSimulateFailure string =
    let
        simpleFailure result =
            case result of
                EventFailure name html ->
                    Ok ("Event.expectEvent: I found a node, but it does not listen for \"" ++ name ++ "\" events like I expected it would.")

                _ ->
                    Err (pleaseReport "Got a failure message from Test.Html.Query that we couldn't parse: " ++ string)
    in
    parseFailureReport string
        |> Result.andThen simpleFailure
        |> Result.withDefault (pleaseReport "Got a failure message from Test.Html.Query that we couldn't parse: " ++ string)
