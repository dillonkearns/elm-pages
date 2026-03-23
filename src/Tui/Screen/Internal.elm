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

{-| Internal module for Screen types and flattening. NOT exposed to users.
-}

import Ansi.Color


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
            let
                allFirstLineSpans : List Span
                allFirstLineSpans =
                    items
                        |> List.concatMap
                            (\item ->
                                case flattenToSpanLines toFlatStyle item of
                                    [] ->
                                        []

                                    first :: _ ->
                                        first
                            )
            in
            [ allFirstLineSpans ]


spanToScreen : (FlatStyle -> style) -> Span -> Screen style
spanToScreen fromFlatStyle span =
    ScreenStyled (fromFlatStyle span.style) span.text


spansToScreen : (FlatStyle -> style) -> List Span -> Screen style
spansToScreen fromFlatStyle spans =
    case spans of
        [] ->
            ScreenEmpty

        _ ->
            spans
                |> List.map (spanToScreen fromFlatStyle)
                |> ScreenConcat


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
                        String.length span.text
                in
                if spanLen <= remaining then
                    span :: truncateSpans (remaining - spanLen) rest

                else if remaining <= 1 then
                    [ { span | text = "\u{2026}" } ]

                else
                    [ { span | text = String.left (remaining - 1) span.text ++ "\u{2026}" } ]


{-| Wrap a flat list of spans into lines, each fitting within maxWidth.
-}
wrapSpans : Int -> List Span -> List (List Span)
wrapSpans maxWidth spans =
    let
        chars : List { ch : Char, style : FlatStyle }
        chars =
            spans
                |> List.concatMap
                    (\span ->
                        String.toList span.text
                            |> List.map (\ch -> { ch = ch, style = span.style })
                    )
    in
    wrapChars maxWidth chars


{-| Greedy word-wrap on a flat character list.
-}
wrapChars : Int -> List { ch : Char, style : FlatStyle } -> List (List Span)
wrapChars maxWidth chars =
    -- elm-review: known-unoptimized-recursion
    if List.isEmpty chars then
        []

    else if List.length chars <= maxWidth then
        -- Everything fits on one line
        [ charsToSpans chars ]

    else
        let
            -- Take up to maxWidth characters as the candidate line
            lineChars : List { ch : Char, style : FlatStyle }
            lineChars =
                List.take maxWidth chars

            -- Check if the character right after maxWidth is a space
            nextChar : Maybe Char
            nextChar =
                List.drop maxWidth chars |> List.head |> Maybe.map .ch

            -- Check if the last char in lineChars is a space
            lastCharIsSpace : Bool
            lastCharIsSpace =
                List.drop (maxWidth - 1) lineChars |> List.head |> Maybe.map .ch |> (==) (Just ' ')
        in
        if nextChar == Just ' ' || lastCharIsSpace then
            let
                trimmedLine : List { ch : Char, style : FlatStyle }
                trimmedLine =
                    trimTrailingSpaces lineChars

                restChars : List { ch : Char, style : FlatStyle }
                restChars =
                    List.drop maxWidth chars |> dropWhile (\c -> c.ch == ' ')
            in
            charsToSpans trimmedLine :: wrapChars maxWidth restChars

        else
            let
                lastSpaceIdx : Maybe Int
                lastSpaceIdx =
                    lineChars
                        |> List.indexedMap Tuple.pair
                        |> List.filterMap
                            (\( i, c ) ->
                                if c.ch == ' ' then
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
                        linePart : List { ch : Char, style : FlatStyle }
                        linePart =
                            List.take spaceIdx lineChars

                        restPart : List { ch : Char, style : FlatStyle }
                        restPart =
                            List.drop (spaceIdx + 1) chars
                    in
                    charsToSpans linePart :: wrapChars maxWidth restPart

                Nothing ->
                    charsToSpans lineChars
                        :: wrapChars maxWidth (List.drop maxWidth chars)


trimTrailingSpaces : List { ch : Char, style : FlatStyle } -> List { ch : Char, style : FlatStyle }
trimTrailingSpaces chars =
    List.reverse chars
        |> dropWhile (\c -> c.ch == ' ')
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


charsToSpans : List { ch : Char, style : FlatStyle } -> List Span
charsToSpans chars =
    -- elm-review: known-unoptimized-recursion
    case chars of
        [] ->
            []

        first :: rest ->
            let
                sameStyle : List { ch : Char, style : FlatStyle }
                sameStyle =
                    takeWhile (\c -> c.style == first.style) rest

                spanText : String
                spanText =
                    String.fromList
                        (first.ch :: List.map .ch sameStyle)

                remaining : List { ch : Char, style : FlatStyle }
                remaining =
                    List.drop (List.length sameStyle) rest
            in
            { text = spanText, style = first.style } :: charsToSpans remaining


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
