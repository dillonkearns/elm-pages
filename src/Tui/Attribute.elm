module Tui.Attribute exposing (Attribute(..))

{-| Text decoration attributes for styled terminal output. Used with
[`Tui.Screen.withAttributes`](Tui-Screen#withAttributes) to apply a dynamic
set of attributes to a `Screen`, and with
[`Tui.Screen.Advanced.styleAttributes`](Tui-Screen-Advanced#styleAttributes)
to inspect the attribute list on an existing `Style`.

    import Tui.Attribute as Attr
    import Tui.Screen as Screen

    Screen.text "Heading"
        |> Screen.withAttributes [ Attr.Bold, Attr.Underline ]

For the common case of applying a single attribute to a `Screen`, prefer the
dedicated builders ([`Tui.Screen.bold`](Tui-Screen#bold),
[`Tui.Screen.italic`](Tui-Screen#italic), etc.) directly.

@docs Attribute

-}


{-| A text decoration attribute.
-}
type Attribute
    = Bold
    | Dim
    | Italic
    | Underline
    | Strikethrough
    | Inverse
