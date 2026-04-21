module Test.PagesProgram.Selector exposing
    ( Selector
    , text, exactText, tag, class, classes, exactClassName, id, value, attribute
    , containing, all
    , disabled, checked, selected, style
    )

{-| Labeled selectors for the elm-pages visual test runner.

Mirrors every constructor in [`Test.Html.Selector`](https://package.elm-lang.org/packages/elm-explorations/test/latest/Test-Html-Selector)
so that every selector you use in a `Test.PagesProgram` assertion carries a
human-readable label. The visual test runner displays these labels in the
command log sidebar, making assertions instantly scannable without reading
source code.

    import Test.PagesProgram.Selector as Selector

    test
        |> PagesProgram.ensureViewHas [ Selector.text "Welcome" ]
        |> PagesProgram.ensureViewHasNot [ Selector.value "deleted item" ]
        |> PagesProgram.done

@docs Selector


## Matching by content

@docs text, exactText, tag, class, classes, exactClassName, id, value, attribute


## Combining

@docs containing, all


## Form state

@docs disabled, checked, selected


## Inline styles

@docs style

-}

import Html
import Test.PagesProgram.Selector.Internal as Internal


{-| A selector that carries both a real `Test.Html.Selector.Selector` for DOM
querying and a human-readable label for display in the visual test runner.
-}
type alias Selector =
    Internal.Selector


{-| Match elements containing the given text (substring match).

    Selector.text "Hello"
    -- label: text "Hello"

-}
text : String -> Selector
text =
    Internal.text


{-| Match elements containing exactly the given text.

    Selector.exactText "Log in"
    -- label: exactText "Log in"

-}
exactText : String -> Selector
exactText =
    Internal.exactText


{-| Match elements with the given tag name.

    Selector.tag "button"
    -- label: <button>

-}
tag : String -> Selector
tag =
    Internal.tag


{-| Match elements that have the given CSS class.

    Selector.class "todo-count"
    -- label: .todo-count

-}
class : String -> Selector
class =
    Internal.class


{-| Match elements that have all of the given CSS classes.

    Selector.classes [ "btn", "btn-primary" ]
    -- label: classes [btn, btn-primary]

-}
classes : List String -> Selector
classes =
    Internal.classes


{-| Match elements whose `className` attribute equals the given string exactly.

    Selector.exactClassName "btn primary"
    -- label: className="btn primary"

-}
exactClassName : String -> Selector
exactClassName =
    Internal.exactClassName


{-| Match elements with the given id.

    Selector.id "main"
    -- label: #main

-}
id : String -> Selector
id =
    Internal.id


{-| Match elements with the given `value` attribute. This is a shorthand
for the common pattern `Selector.attribute "value=..." (Attr.value ...)`.

    Selector.value "Buy milk"
    -- label: value="Buy milk"

-}
value : String -> Selector
value =
    Internal.value


{-| Match elements with the given HTML attribute. You provide a label and the
attribute value.

    Selector.attribute "href=\"/about\"" (Attr.href "/about")
    -- label: href="/about"

-}
attribute : String -> Html.Attribute Never -> Selector
attribute =
    Internal.attribute


{-| Match elements that contain descendants matching all the given selectors.

    Selector.containing [ Selector.value "Buy milk" ]
    -- label: :has(value="Buy milk")

-}
containing : List Selector -> Selector
containing =
    Internal.containing


{-| Combine selectors into one that requires all of them to match a single
element. Useful for composing selectors inside [`containing`](#containing) or
for grouping related matchers.

    Selector.containing
        [ Selector.all [ Selector.tag "button", Selector.class "primary" ] ]
    -- label: :has(all [<button>, .primary])

-}
all : List Selector -> Selector
all =
    Internal.all


{-| Match elements by their disabled state.

    Selector.disabled True
    -- label: [disabled]

-}
disabled : Bool -> Selector
disabled =
    Internal.disabled


{-| Match form inputs by their checked state.

    Selector.checked True
    -- label: [checked]

-}
checked : Bool -> Selector
checked =
    Internal.checked


{-| Match `<option>` elements by their selected state.

    Selector.selected True
    -- label: [selected]

-}
selected : Bool -> Selector
selected =
    Internal.selected


{-| Match elements with the given inline style declaration.

    Selector.style "color" "red"
    -- label: style "color: red"

-}
style : String -> String -> Selector
style =
    Internal.style
