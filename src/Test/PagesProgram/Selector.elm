module Test.PagesProgram.Selector exposing
    ( Selector
    , text, tag, class, id, value, attribute, containing, disabled
    , raw
    )

{-| Labeled selectors for the elm-pages visual test runner.

These wrap `Test.Html.Selector` so that every selector carries a human-readable
label. The visual test runner displays these labels in the command log sidebar,
making assertions instantly scannable without reading source code.

    import Test.PagesProgram.Selector as Selector

    test
        |> PagesProgram.ensureViewHas [ Selector.text "Welcome" ]
        |> PagesProgram.ensureViewHasNot [ Selector.value "deleted item" ]
        |> PagesProgram.done

@docs Selector

@docs text, tag, class, id, value, attribute, containing, disabled

@docs raw

-}

import Test.Html.Selector as HtmlSelector
import Test.PagesProgram.Selector.Internal as Internal


{-| A selector that carries both a real `Test.Html.Selector.Selector` for DOM
querying and a human-readable label for display in the visual test runner.
-}
type alias Selector =
    Internal.Selector


{-| Match elements containing the given text.

    Selector.text "Hello"
    -- label: text "Hello"

-}
text : String -> Selector
text =
    Internal.text


{-| Match elements with the given tag name.

    Selector.tag "button"
    -- label: <button>

-}
tag : String -> Selector
tag =
    Internal.tag


{-| Match elements with the given CSS class.

    Selector.class "todo-count"
    -- label: .todo-count

-}
class : String -> Selector
class =
    Internal.class


{-| Match elements with the given id.

    Selector.id "main"
    -- label: #main

-}
id : String -> Selector
id =
    Internal.id


{-| Match elements with the given `value` attribute. This is a shorthand
for the common pattern `Selector.attribute (Attr.value ...)`.

    Selector.value "Buy milk"
    -- label: value="Buy milk"

-}
value : String -> Selector
value =
    Internal.value


{-| Match elements with the given HTML attribute. You provide a label
and the attribute.

    Selector.attribute "href" (Attr.href "/about")
    -- label: href="/about"

-}
attribute : String -> HtmlSelector.Selector -> Selector
attribute =
    Internal.attribute


{-| Match elements that contain descendants matching all the given selectors.

    Selector.containing [ Selector.value "Buy milk" ]
    -- label: :has(value="Buy milk")

-}
containing : List Selector -> Selector
containing =
    Internal.containing


{-| Match elements based on their disabled state.

    Selector.disabled True
    -- label: [disabled]

-}
disabled : Bool -> Selector
disabled =
    Internal.disabled


{-| Escape hatch: wrap any `Test.Html.Selector.Selector` with a custom label.
Use this for selectors not covered by the convenience constructors above.

    Selector.raw "custom-attr" (HtmlSelector.attribute (Attr.attribute "data-testid" "foo"))

-}
raw : String -> HtmlSelector.Selector -> Selector
raw =
    Internal.raw
