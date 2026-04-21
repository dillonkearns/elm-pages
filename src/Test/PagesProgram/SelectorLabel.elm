module Test.PagesProgram.SelectorLabel exposing
    ( extractLabels
    , parseLabelToAssertion
    )

{-| Derive human-readable labels and structured highlight data from
`Test.Html.Selector.Selector` values.

Rather than carrying metadata alongside each selector, we extract it on
demand by running `Test.Html.Query.has` against an empty query and catching
the forced failure via `Test.Runner.getFailureReason`. The description
string it produces contains a per-selector `✓ has ...` / `✗ has ...` line in
the exact format Test.Html.Query uses in its own error messages.

One force-failure per `Query.has` call yields labels for every selector in
the list; there is no per-selector overhead.

-}

import Html
import Test.Html.Query
import Test.Html.Selector
import Test.PagesProgram.Internal exposing (AssertionSelector(..))
import Test.Runner


{-| Derive a human-readable label for each selector in the list. The labels
match the format Test.Html.Query uses in failure messages (e.g. `tag "button"`,
`class "greeting"`, `text "Hello"`).

An empty list returns an empty list and never forces a failure.

-}
extractLabels : List Test.Html.Selector.Selector -> List String
extractLabels userSelectors =
    case userSelectors of
        [] ->
            []

        _ ->
            let
                -- Guarantee failure by prepending a sentinel tag that
                -- cannot appear in any rendered view. Query.has reports
                -- every selector (pass or fail) on its own line, so all
                -- user labels come through regardless of the sentinel.
                sentinel : Test.Html.Selector.Selector
                sentinel =
                    Test.Html.Selector.tag "elm-pages-label-extractor-sentinel"

                expectation =
                    Html.text ""
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has (sentinel :: userSelectors)
            in
            case Test.Runner.getFailureReason expectation of
                Just reason ->
                    reason.description
                        |> String.lines
                        |> List.filterMap parseHasLine
                        |> List.drop 1

                Nothing ->
                    -- Unreachable: the sentinel guarantees failure.
                    List.map (\_ -> "<unknown selector>") userSelectors


{-| Extract the selector text from a `✓ has ...` or `✗ has ...` line.
Returns `Nothing` for lines in other sections of the description.
-}
parseHasLine : String -> Maybe String
parseHasLine line =
    let
        trimmed : String
        trimmed =
            String.trim line
    in
    if String.startsWith "✗ has " trimmed then
        Just (String.dropLeft (String.length "✗ has ") trimmed)

    else if String.startsWith "✓ has " trimmed then
        Just (String.dropLeft (String.length "✓ has ") trimmed)

    else
        Nothing


{-| Parse a label string (produced by [`extractLabels`](#extractLabels))
into a structured `AssertionSelector` the visual runner can use for DOM
highlighting. Unknown shapes fall through to `ByOther`, which the viewer
displays but does not highlight.
-}
parseLabelToAssertion : String -> AssertionSelector
parseLabelToAssertion label =
    let
        trimmed : String
        trimmed =
            String.trim label
    in
    parseStartsWith "tag " trimmed (\rest -> Maybe.map ByTag_ (parseQuotedArg rest))
        |> orElse (\_ -> parseStartsWith "class " trimmed (\rest -> Maybe.map ByClass (parseQuotedArg rest)))
        |> orElse (\_ -> parseStartsWith "exact text " trimmed (\rest -> Maybe.map ByText (parseQuotedArg rest)))
        |> orElse (\_ -> parseStartsWith "text " trimmed (\rest -> Maybe.map ByText (parseQuotedArg rest)))
        |> orElse (\_ -> parseAttribute trimmed)
        |> orElse (\_ -> parseContaining trimmed)
        |> Maybe.withDefault (ByOther trimmed)


{-| Try a prefix match; if matched, run the continuation on the rest.
-}
parseStartsWith : String -> String -> (String -> Maybe AssertionSelector) -> Maybe AssertionSelector
parseStartsWith prefix input cont =
    if String.startsWith prefix input then
        cont (String.dropLeft (String.length prefix) input)

    else
        Nothing


{-| Parse a single double-quoted string argument. Returns `Nothing` if the
input doesn't start with `"` or has no closing `"`.
-}
parseQuotedArg : String -> Maybe String
parseQuotedArg input =
    let
        trimmed : String
        trimmed =
            String.trimLeft input
    in
    if String.startsWith "\"" trimmed then
        let
            body : String
            body =
                String.dropLeft 1 trimmed
        in
        case String.indexes "\"" body of
            i :: _ ->
                Just (String.left i body)

            [] ->
                Nothing

    else
        Nothing


{-| Parse `attribute "id" "main"` and `attribute "value" "foo"` into the
specific `ById_` / `ByValue` variants; other attributes fall through to
`ByOther`.
-}
parseAttribute : String -> Maybe AssertionSelector
parseAttribute trimmed =
    if String.startsWith "attribute \"id\" " trimmed then
        Maybe.map ById_ (parseQuotedArg (String.dropLeft (String.length "attribute \"id\" ") trimmed))

    else if String.startsWith "attribute \"value\" " trimmed then
        Maybe.map ByValue (parseQuotedArg (String.dropLeft (String.length "attribute \"value\" ") trimmed))

    else
        Nothing


{-| Parse `containing [ <inner1>, <inner2>, ... ]` recursively. We split
the bracketed body on top-level commas and recurse into each child so that
highlights propagate through nested selectors.
-}
parseContaining : String -> Maybe AssertionSelector
parseContaining trimmed =
    if String.startsWith "containing [ " trimmed then
        let
            inner : String
            inner =
                trimmed
                    |> String.dropLeft (String.length "containing [ ")
        in
        case String.indexes "]" inner of
            _ :: _ ->
                -- Use the last `]` as the closing bracket; if the inner
                -- selectors have their own brackets (e.g. nested
                -- `containing`), this keeps them grouped together.
                let
                    lastCloseIndex : Int
                    lastCloseIndex =
                        inner
                            |> String.indexes "]"
                            |> List.reverse
                            |> List.head
                            |> Maybe.withDefault (String.length inner)

                    body : String
                    body =
                        String.left lastCloseIndex inner
                in
                Just (ByContaining (List.map parseLabelToAssertion (splitTopLevelCommas body)))

            [] ->
                Nothing

    else
        Nothing


{-| Split on commas that are outside of any nested `[...]` or `"..."`.
-}
splitTopLevelCommas : String -> List String
splitTopLevelCommas body =
    let
        step : Char -> { depth : Int, inString : Bool, current : String, pieces : List String } -> { depth : Int, inString : Bool, current : String, pieces : List String }
        step ch state =
            if state.inString then
                if ch == '"' then
                    { state | inString = False, current = state.current ++ String.fromChar ch }

                else
                    { state | current = state.current ++ String.fromChar ch }

            else if ch == '"' then
                { state | inString = True, current = state.current ++ String.fromChar ch }

            else if ch == '[' then
                { state | depth = state.depth + 1, current = state.current ++ String.fromChar ch }

            else if ch == ']' then
                { state | depth = state.depth - 1, current = state.current ++ String.fromChar ch }

            else if ch == ',' && state.depth == 0 then
                { state | current = "", pieces = state.pieces ++ [ String.trim state.current ] }

            else
                { state | current = state.current ++ String.fromChar ch }

        final : { depth : Int, inString : Bool, current : String, pieces : List String }
        final =
            body
                |> String.toList
                |> List.foldl step { depth = 0, inString = False, current = "", pieces = [] }
    in
    final.pieces ++ [ String.trim final.current ]


{-| Run `fallback ()` when `first` is `Nothing`, otherwise keep `first`.
-}
orElse : (() -> Maybe a) -> Maybe a -> Maybe a
orElse fallback first =
    case first of
        Just _ ->
            first

        Nothing ->
            fallback ()
