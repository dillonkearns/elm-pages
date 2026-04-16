module Tui.Screen.Advanced exposing
    ( Line, Span, toLines
    , fromLine
    )

{-| Framework-level helpers for inspecting and rebuilding styled terminal lines.

Most app code should stay in [`Tui.Screen`](Tui-Screen). This module is for
packages like `tui-widgets` that need to preserve styles while transforming
rendered text.

    import Tui.Screen as Screen
    import Tui.Screen.Advanced as Advanced

    screen : Screen.Screen
    screen =
        Screen.concat
            [ Screen.text "hello "
            , Screen.text "world" |> Screen.fg Ansi.Color.green
            ]

    screen
        |> Advanced.toLines
        |> List.head
        |> Maybe.withDefault []
        |> Advanced.fromLine
        |> Screen.toString


## Lines

@docs Line, Span, toLines


## Rebuilding

@docs fromLine

-}

import Tui.Screen
import Tui.Screen.Internal as Internal


{-| A rendered screen line represented as styled spans.

    import Tui.Screen.Advanced as Advanced

    line : Advanced.Line
    line =
        []

-}
type alias Line =
    List Span


{-| A styled segment within a rendered line.

    import Tui.Screen as Screen
    import Tui.Screen.Advanced as Advanced

    span : Advanced.Span
    span =
        { text = "hello"
        , style = Screen.plain
        }

-}
type alias Span =
    { text : String
    , style : Tui.Screen.Style
    }


{-| Flatten a `Tui.Screen.Screen` into rendered lines of styled spans.

    import Ansi.Color
    import Tui.Screen as Screen
    import Tui.Screen.Advanced as Advanced

    lines : List Advanced.Line
    lines =
        Screen.concat
            [ Screen.text "hello "
            , Screen.text "world" |> Screen.fg Ansi.Color.green
            ]
            |> Advanced.toLines

-}
toLines : Tui.Screen.Screen -> List Line
toLines screen =
    Internal.flattenToSpanLines styleToFlatStyle screen
        |> List.map (List.map spanFromInternal)


{-| Rebuild a single rendered line from styled spans.

An empty line becomes [`Tui.Screen.blank`](Tui-Screen#blank), preserving the
fact that it takes up one terminal row.

    import Tui.Screen as Screen
    import Tui.Screen.Advanced as Advanced

    screen : Screen.Screen
    screen =
        [ { text = "Status", style = Screen.plain } ]
            |> Advanced.fromLine

-}
fromLine : Line -> Tui.Screen.Screen
fromLine line =
    if List.isEmpty line then
        Tui.Screen.blank

    else
        line
            |> List.map spanToInternal
            |> Internal.spansToScreen flatStyleToStyle


styleToFlatStyle : Tui.Screen.Style -> Internal.FlatStyle
styleToFlatStyle style =
    let
        defaultStyle : Internal.FlatStyle
        defaultStyle =
            Internal.defaultFlatStyle

        base : Internal.FlatStyle
        base =
            { defaultStyle
                | foreground = style.fg
                , background = style.bg
                , hyperlink = style.hyperlink
            }
    in
    List.foldl applyAttr base style.attributes


applyAttr : Tui.Screen.Attribute -> Internal.FlatStyle -> Internal.FlatStyle
applyAttr attr flatStyle =
    case attr of
        Tui.Screen.Bold ->
            { flatStyle | bold = True }

        Tui.Screen.Dim ->
            { flatStyle | dim = True }

        Tui.Screen.Italic ->
            { flatStyle | italic = True }

        Tui.Screen.Underline ->
            { flatStyle | underline = True }

        Tui.Screen.Strikethrough ->
            { flatStyle | strikethrough = True }

        Tui.Screen.Inverse ->
            { flatStyle | inverse = True }


flatStyleToAttrs : Internal.FlatStyle -> List Tui.Screen.Attribute
flatStyleToAttrs style =
    List.filterMap identity
        [ if style.bold then
            Just Tui.Screen.Bold

          else
            Nothing
        , if style.dim then
            Just Tui.Screen.Dim

          else
            Nothing
        , if style.italic then
            Just Tui.Screen.Italic

          else
            Nothing
        , if style.underline then
            Just Tui.Screen.Underline

          else
            Nothing
        , if style.strikethrough then
            Just Tui.Screen.Strikethrough

          else
            Nothing
        , if style.inverse then
            Just Tui.Screen.Inverse

          else
            Nothing
        ]


flatStyleToStyle : Internal.FlatStyle -> Tui.Screen.Style
flatStyleToStyle style =
    { fg = style.foreground
    , bg = style.background
    , attributes = flatStyleToAttrs style
    , hyperlink = style.hyperlink
    }


spanToInternal : Span -> Internal.Span
spanToInternal span =
    { text = span.text
    , style = styleToFlatStyle span.style
    }


spanFromInternal : Internal.Span -> Span
spanFromInternal span =
    { text = span.text
    , style = flatStyleToStyle span.style
    }
