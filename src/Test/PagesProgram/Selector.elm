module Test.PagesProgram.Selector exposing
    ( Selector
    , text, tag, class, id, value, attribute, containing, disabled
    , raw
    , toLabel, toHtmlSelectors
    , AssertionSelector(..), toAssertionSelectors
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

@docs toLabel, toHtmlSelectors

@docs AssertionSelector, toAssertionSelectors

-}

import Html.Attributes as Attr
import Test.Html.Selector as HtmlSelector


{-| A selector that carries both a real `Test.Html.Selector.Selector` for DOM
querying and a human-readable label for display in the visual test runner.
-}
type Selector
    = Selector String AssertionSelector HtmlSelector.Selector


{-| Structured selector data for highlighting elements in the visual test runner.
Each variant maps to a CSS selector strategy in the highlight JS.
-}
type AssertionSelector
    = ByText String
    | ByClass String
    | ById_ String
    | ByTag_ String
    | ByValue String
    | ByContaining (List AssertionSelector)
    | ByOther String


{-| Match elements containing the given text.

    Selector.text "Hello"
    -- label: text "Hello"

-}
text : String -> Selector
text s =
    Selector ("text \"" ++ s ++ "\"") (ByText s) (HtmlSelector.text s)


{-| Match elements with the given tag name.

    Selector.tag "button"
    -- label: <button>

-}
tag : String -> Selector
tag s =
    Selector ("<" ++ s ++ ">") (ByTag_ s) (HtmlSelector.tag s)


{-| Match elements with the given CSS class.

    Selector.class "todo-count"
    -- label: .todo-count

-}
class : String -> Selector
class s =
    Selector ("." ++ s) (ByClass s) (HtmlSelector.class s)


{-| Match elements with the given id.

    Selector.id "main"
    -- label: #main

-}
id : String -> Selector
id s =
    Selector ("#" ++ s) (ById_ s) (HtmlSelector.id s)


{-| Match elements with the given `value` attribute. This is a shorthand
for the common pattern `Selector.attribute (Attr.value ...)`.

    Selector.value "Buy milk"
    -- label: value="Buy milk"

-}
value : String -> Selector
value s =
    Selector ("value=\"" ++ s ++ "\"") (ByValue s) (HtmlSelector.attribute (Attr.value s))


{-| Match elements with the given HTML attribute. You provide a label
and the attribute.

    Selector.attribute "href" (Attr.href "/about")
    -- label: href="/about"

-}
attribute : String -> HtmlSelector.Selector -> Selector
attribute label sel =
    Selector label (ByOther label) sel


{-| Match elements that contain descendants matching all the given selectors.

    Selector.containing [ Selector.value "Buy milk" ]
    -- label: :has(value="Buy milk")

-}
containing : List Selector -> Selector
containing selectors =
    Selector
        (":has(" ++ labelsString selectors ++ ")")
        (ByContaining (List.map unwrapAssertion selectors))
        (HtmlSelector.containing (List.map unwrapHtml selectors))


{-| Match elements based on their disabled state.

    Selector.disabled True
    -- label: [disabled]

-}
disabled : Bool -> Selector
disabled b =
    Selector
        (if b then
            "[disabled]"

         else
            ":not([disabled])"
        )
        (ByOther
            (if b then
                "[disabled]"

             else
                ":not([disabled])"
            )
        )
        (HtmlSelector.disabled b)


{-| Escape hatch: wrap any `Test.Html.Selector.Selector` with a custom label.
Use this for selectors not covered by the convenience constructors above.

    Selector.raw "custom-attr" (HtmlSelector.attribute (Attr.attribute "data-testid" "foo"))

-}
raw : String -> HtmlSelector.Selector -> Selector
raw label sel =
    Selector label (ByOther label) sel


{-| Get a human-readable label from a list of selectors.
Multiple selectors are comma-separated.

    toLabel [ Selector.text "Hello", Selector.class "greeting" ]
    -- "text \"Hello\", .greeting"

-}
toLabel : List Selector -> String
toLabel selectors =
    selectors
        |> List.map (\(Selector label _ _) -> label)
        |> String.join ", "


{-| Extract the underlying `Test.Html.Selector.Selector` values for use with
`Test.Html.Query` functions.
-}
toHtmlSelectors : List Selector -> List HtmlSelector.Selector
toHtmlSelectors selectors =
    List.map unwrapHtml selectors


{-| Extract the `AssertionSelector` values for use by the visual test runner
to highlight matching elements in the preview.
-}
toAssertionSelectors : List Selector -> List AssertionSelector
toAssertionSelectors selectors =
    List.map unwrapAssertion selectors



-- INTERNAL


unwrapHtml : Selector -> HtmlSelector.Selector
unwrapHtml (Selector _ _ sel) =
    sel


unwrapAssertion : Selector -> AssertionSelector
unwrapAssertion (Selector _ a _) =
    a


labelsString : List Selector -> String
labelsString selectors =
    selectors
        |> List.map (\(Selector label _ _) -> label)
        |> String.join ", "
