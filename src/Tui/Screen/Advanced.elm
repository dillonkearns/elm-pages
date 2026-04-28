module Tui.Screen.Advanced exposing
    ( Line, Span, toLines
    , fromLine
    , styleForeground, styleBackground, styleAttributes, styleHyperlink
    , FlatStyle, styleToFlatStyle, flatStyleToStyle
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


## Flat Style Records

For lower-level access, `FlatStyle` is a plain record with one `Bool`
field per [`Tui.Attribute.Attribute`](Tui-Attribute#Attribute) plus the
color/hyperlink fields. Conversion to/from a `Style` is provided for
framework-level consumers that need to manipulate styles as records.

@docs FlatStyle, styleToFlatStyle, flatStyleToStyle

-}

import Ansi.Color
import Tui.Attribute exposing (Attribute)
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


{-| Flat record representation of a [`Style`](Tui-Screen#Style), with one
`Bool` per attribute plus color and hyperlink fields.
-}
type alias FlatStyle =
    Internal.FlatStyle


{-| Convert an opaque `Style` to its flat record form.
-}
styleToFlatStyle : Tui.Screen.Style -> FlatStyle
styleToFlatStyle =
    Internal.styleToFlatStyle


{-| Convert a flat record back to an opaque `Style`. Inverse of
[`styleToFlatStyle`](#styleToFlatStyle).
-}
flatStyleToStyle : FlatStyle -> Tui.Screen.Style
flatStyleToStyle =
    Internal.flatStyleToStyle


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
    (styleToFlatStyle style).foreground


{-| Read the background color of a [`Style`](Tui-Screen#Style).
-}
styleBackground : Tui.Screen.Style -> Maybe Ansi.Color.Color
styleBackground style =
    (styleToFlatStyle style).background


{-| Read the attribute list of a [`Style`](Tui-Screen#Style).

    import Tui.Attribute as Attr
    import Tui.Screen.Advanced as Advanced

    if List.member Attr.Bold (Advanced.styleAttributes span.style) then
        ...

-}
styleAttributes : Tui.Screen.Style -> List Attribute
styleAttributes style =
    let
        flat : FlatStyle
        flat =
            styleToFlatStyle style
    in
    []
        |> (if flat.strikethrough then (::) Tui.Attribute.Strikethrough else identity)
        |> (if flat.underline then (::) Tui.Attribute.Underline else identity)
        |> (if flat.italic then (::) Tui.Attribute.Italic else identity)
        |> (if flat.inverse then (::) Tui.Attribute.Inverse else identity)
        |> (if flat.dim then (::) Tui.Attribute.Dim else identity)
        |> (if flat.bold then (::) Tui.Attribute.Bold else identity)


{-| Read the hyperlink URL of a [`Style`](Tui-Screen#Style), if any.
-}
styleHyperlink : Tui.Screen.Style -> Maybe String
styleHyperlink style =
    (styleToFlatStyle style).hyperlink
