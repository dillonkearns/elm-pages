module Tui.Screen.Advanced exposing
    ( Line, Span, toLines
    , fromLine
    , styleForeground, styleBackground, styleAttributes, styleHyperlink
    )

{-| Framework-level helpers for inspecting and rebuilding styled terminal lines.

Most app code should stay in [`Tui.Screen`](Tui-Screen). Reach for this module
when you need to preserve styling while transforming rendered text. Typical use
cases are highlighting search matches in an already-styled buffer, applying
syntax coloring to rendered output, splitting lines at arbitrary character
positions without losing styles, or implementing diff-style overlays. The
`tui-widgets` package uses this internally for its search and layout features.

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


## Reading a Style

Getters for the `style` field of a [`Span`](#Span). The `Style` type from
[`Tui.Screen`](Tui-Screen) is opaque so that future releases can add
fields without breaking user code; these getters are the supported way
to inspect it.

@docs styleForeground, styleBackground, styleAttributes, styleHyperlink

-}

import Ansi.Color
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


{-| A styled segment within a rendered line. Obtain spans by calling
[`toLines`](#toLines) on a rendered `Tui.Screen.Screen`. Inspect the `style`
field with [`styleForeground`](#styleForeground),
[`styleBackground`](#styleBackground),
[`styleAttributes`](#styleAttributes), and
[`styleHyperlink`](#styleHyperlink).
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

Typical use is a round-trip: obtain spans with [`toLines`](#toLines), transform
them (e.g. to highlight search matches), and reassemble with `fromLine`.

    import Tui.Screen as Screen
    import Tui.Screen.Advanced as Advanced

    source : Screen.Screen
    source =
        Screen.text "hello" |> Screen.bold

    roundTripped : Screen.Screen
    roundTripped =
        source
            |> Advanced.toLines
            |> List.head
            |> Maybe.withDefault []
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
styleToFlatStyle =
    Tui.Screen.styleToFlatStyle


flatStyleToStyle : Internal.FlatStyle -> Tui.Screen.Style
flatStyleToStyle =
    Tui.Screen.flatStyleToStyle


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


{-| Read the foreground color of a [`Style`](Tui-Screen#Style).
-}
styleForeground : Tui.Screen.Style -> Maybe Ansi.Color.Color
styleForeground style =
    (Tui.Screen.styleToFlatStyle style).foreground


{-| Read the background color of a [`Style`](Tui-Screen#Style).
-}
styleBackground : Tui.Screen.Style -> Maybe Ansi.Color.Color
styleBackground style =
    (Tui.Screen.styleToFlatStyle style).background


{-| Read the attribute list of a [`Style`](Tui-Screen#Style).

    import Tui.Screen as Screen
    import Tui.Screen.Advanced as Advanced

    if List.member Screen.Bold (Advanced.styleAttributes span.style) then
        ...

-}
styleAttributes : Tui.Screen.Style -> List Tui.Screen.Attribute
styleAttributes style =
    let
        flat : Tui.Screen.FlatStyle
        flat =
            Tui.Screen.styleToFlatStyle style
    in
    []
        |> (if flat.strikethrough then (::) Tui.Screen.Strikethrough else identity)
        |> (if flat.underline then (::) Tui.Screen.Underline else identity)
        |> (if flat.italic then (::) Tui.Screen.Italic else identity)
        |> (if flat.inverse then (::) Tui.Screen.Inverse else identity)
        |> (if flat.dim then (::) Tui.Screen.Dim else identity)
        |> (if flat.bold then (::) Tui.Screen.Bold else identity)


{-| Read the hyperlink URL of a [`Style`](Tui-Screen#Style), if any.
-}
styleHyperlink : Tui.Screen.Style -> Maybe String
styleHyperlink style =
    (Tui.Screen.styleToFlatStyle style).hyperlink
