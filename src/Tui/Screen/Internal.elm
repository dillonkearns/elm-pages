module Tui.Screen.Internal exposing
    ( Screen(..)
    , Span, FlatStyle
    , flattenToSpanLines, defaultFlatStyle
    , applyStyle
    , spanToScreen, spansToScreen
    , truncateSpans
    , wrapSpans
    , extractStyle
    )

{-| Internal module for Screen types and flattening.

@docs Screen, Span, FlatStyle
@docs flattenToSpanLines, defaultFlatStyle
@docs applyStyle
@docs spanToScreen, spansToScreen
@docs truncateSpans
@docs wrapSpans
@docs extractStyle

-}

import Ansi.Color
import String.Graphemes as Graphemes


{-| Type representing terminal output, parameterized over the style type.
-}
type Screen style
    = ScreenText String
    | ScreenStyled style String
    | ScreenLines (List (Screen style))
    | ScreenConcat (List (Screen style))
    | ScreenEmpty


{-| A styled text span.
-}
type alias Span =
    { text : String
    , style : FlatStyle
    }


{-| Resolved style with all attributes as booleans.
-}
type alias FlatStyle =
    { bold : Bool
    , dim : Bool
    , italic : Bool
    , underline : Bool
    , strikethrough : Bool
    , inverse : Bool
    , foreground : Maybe Ansi.Color.Color
    , background : Maybe Ansi.Color.Color
    , hyperlink : Maybe String
    }


{-| Default style with no attributes set.
-}
defaultFlatStyle : FlatStyle
defaultFlatStyle =
    { bold = False
    , dim = False
    , italic = False
    , underline = False
    , strikethrough = False
    , inverse = False
    , foreground = Nothing
    , background = Nothing
    , hyperlink = Nothing
    }


{-| Apply a style transformation to a Screen. Recursively applies to all
children in compound screens.
-}
applyStyle : style -> (style -> style) -> Screen style -> Screen style
applyStyle defaultStyle transform screen =
    -- elm-review: known-unoptimized-recursion
    case screen of
        ScreenText s ->
            ScreenStyled (transform defaultStyle) s

        ScreenStyled stl s ->
            ScreenStyled (transform stl) s

        ScreenConcat items ->
            ScreenConcat (List.map (applyStyle defaultStyle transform) items)

        ScreenLines items ->
            ScreenLines (List.map (applyStyle defaultStyle transform) items)

        ScreenEmpty ->
            ScreenEmpty


{-| Flatten a Screen tree into a list of lines, where each line
is a list of styled spans.
-}
flattenToSpanLines : (style -> FlatStyle) -> Screen style -> List (List Span)
flattenToSpanLines toFlatStyle screen =
    -- elm-review: known-unoptimized-recursion
    case screen of
        ScreenEmpty ->
            []

        ScreenText s ->
            if String.isEmpty s then
                [ [] ]

            else
                s
                    |> String.split "\n"
                    |> List.map (\line -> [ { text = line, style = defaultFlatStyle } ])

        ScreenStyled stl s ->
            if String.isEmpty s then
                [ [] ]

            else
                let
                    flatStyle : FlatStyle
                    flatStyle =
                        toFlatStyle stl
                in
                s
                    |> String.split "\n"
                    |> List.map (\line -> [ { text = line, style = flatStyle } ])

        ScreenLines items ->
            List.concatMap (flattenToSpanLines toFlatStyle) items

        ScreenConcat items ->
            items
                |> List.map (flattenToSpanLines toFlatStyle)
                |> concatSpanLines


{-| Convert a Span to a Screen.
-}
spanToScreen : (FlatStyle -> style) -> Span -> Screen style
spanToScreen fromFlatStyle span =
    ScreenStyled (fromFlatStyle span.style) span.text


{-| Convert a list of Spans to a Screen.
-}
spansToScreen : (FlatStyle -> style) -> List Span -> Screen style
spansToScreen fromFlatStyle spans =
    case spans of
        [] ->
            ScreenEmpty

        _ ->
            spans
                |> List.map (spanToScreen fromFlatStyle)
                |> ScreenConcat


{-| Truncate spans to fit within a character count, adding an ellipsis if needed.
-}
truncateSpans : Int -> List Span -> List Span
truncateSpans remaining spans =
    -- elm-review: known-unoptimized-recursion
    case spans of
        [] ->
            []

        span :: rest ->
            if remaining <= 0 then
                []

            else
                let
                    spanLen : Int
                    spanLen =
                        Graphemes.length span.text
                in
                if spanLen <= remaining then
                    span :: truncateSpans (remaining - spanLen) rest

                else if remaining <= 1 then
                    [ { span | text = "\u{2026}" } ]

                else
                    [ { span | text = Graphemes.left (remaining - 1) span.text ++ "\u{2026}" } ]


{-| Wrap a flat list of spans into lines, each fitting within maxWidth.
-}
wrapSpans : Int -> List Span -> List (List Span)
wrapSpans maxWidth spans =
    if maxWidth <= 0 then
        []

    else
        let
            graphemes : List { text : String, style : FlatStyle }
            graphemes =
                spans
                    |> List.concatMap spanToGraphemes
        in
        wrapGraphemes maxWidth graphemes


{-| Greedy word-wrap on a flat grapheme list.
-}
wrapGraphemes : Int -> List { text : String, style : FlatStyle } -> List (List Span)
wrapGraphemes maxWidth graphemes =
    -- elm-review: known-unoptimized-recursion
    if List.isEmpty graphemes then
        []

    else if List.length graphemes <= maxWidth then
        -- Everything fits on one line
        [ graphemesToSpans graphemes ]

    else
        let
            lineGraphemes : List { text : String, style : FlatStyle }
            lineGraphemes =
                List.take maxWidth graphemes

            nextGrapheme : Maybe String
            nextGrapheme =
                List.drop maxWidth graphemes |> List.head |> Maybe.map .text

            lastGraphemeIsSpace : Bool
            lastGraphemeIsSpace =
                List.drop (maxWidth - 1) lineGraphemes |> List.head |> Maybe.map .text |> (==) (Just " ")
        in
        if nextGrapheme == Just " " || lastGraphemeIsSpace then
            let
                trimmedLine : List { text : String, style : FlatStyle }
                trimmedLine =
                    trimTrailingSpaces lineGraphemes

                restGraphemes : List { text : String, style : FlatStyle }
                restGraphemes =
                    List.drop maxWidth graphemes |> dropWhile (\grapheme -> grapheme.text == " ")
            in
            graphemesToSpans trimmedLine :: wrapGraphemes maxWidth restGraphemes

        else
            let
                lastSpaceIdx : Maybe Int
                lastSpaceIdx =
                    lineGraphemes
                        |> List.indexedMap Tuple.pair
                        |> List.filterMap
                            (\( i, grapheme ) ->
                                if grapheme.text == " " then
                                    Just i

                                else
                                    Nothing
                            )
                        |> List.reverse
                        |> List.head
            in
            case lastSpaceIdx of
                Just spaceIdx ->
                    let
                        linePart : List { text : String, style : FlatStyle }
                        linePart =
                            List.take spaceIdx lineGraphemes

                        restPart : List { text : String, style : FlatStyle }
                        restPart =
                            List.drop (spaceIdx + 1) graphemes
                    in
                    graphemesToSpans linePart :: wrapGraphemes maxWidth restPart

                Nothing ->
                    graphemesToSpans lineGraphemes
                        :: wrapGraphemes maxWidth (List.drop maxWidth graphemes)


trimTrailingSpaces : List { text : String, style : FlatStyle } -> List { text : String, style : FlatStyle }
trimTrailingSpaces graphemes =
    List.reverse graphemes
        |> dropWhile (\grapheme -> grapheme.text == " ")
        |> List.reverse


dropWhile : (a -> Bool) -> List a -> List a
dropWhile pred list =
    -- elm-review: known-unoptimized-recursion
    case list of
        [] ->
            []

        x :: xs ->
            if pred x then
                dropWhile pred xs

            else
                list


takeWhile : (a -> Bool) -> List a -> List a
takeWhile pred list =
    -- elm-review: known-unoptimized-recursion
    case list of
        [] ->
            []

        x :: xs ->
            if pred x then
                x :: takeWhile pred xs

            else
                []


graphemesToSpans : List { text : String, style : FlatStyle } -> List Span
graphemesToSpans graphemes =
    -- elm-review: known-unoptimized-recursion
    case graphemes of
        [] ->
            []

        first :: rest ->
            let
                sameStyle : List { text : String, style : FlatStyle }
                sameStyle =
                    takeWhile (\c -> c.style == first.style) rest

                spanText : String
                spanText =
                    first.text :: List.map .text sameStyle
                        |> String.concat

                remaining : List { text : String, style : FlatStyle }
                remaining =
                    List.drop (List.length sameStyle) rest
            in
            { text = spanText, style = first.style } :: graphemesToSpans remaining


spanToGraphemes : Span -> List { text : String, style : FlatStyle }
spanToGraphemes span =
    Graphemes.toList span.text
        |> List.map (\grapheme -> { text = grapheme, style = span.style })


concatSpanLines : List (List (List Span)) -> List (List Span)
concatSpanLines lineGroups =
    -- elm-review: known-unoptimized-recursion
    if List.all List.isEmpty lineGroups then
        []

    else
        let
            currentLine : List Span
            currentLine =
                lineGroups
                    |> List.concatMap
                        (\group ->
                            case group of
                                first :: _ ->
                                    first

                                [] ->
                                    []
                        )

            remainingGroups : List (List (List Span))
            remainingGroups =
                lineGroups
                    |> List.map
                        (\group ->
                            case group of
                                _ :: rest ->
                                    rest

                                [] ->
                                    []
                        )
        in
        currentLine :: concatSpanLines remainingGroups


{-| Extract the outermost style from a Screen.
-}
extractStyle : style -> Screen style -> style
extractStyle defaultStyle screen =
    case screen of
        ScreenStyled stl _ ->
            stl

        ScreenConcat items ->
            case items of
                (ScreenStyled stl _) :: _ ->
                    stl

                _ ->
                    defaultStyle

        _ ->
            defaultStyle
