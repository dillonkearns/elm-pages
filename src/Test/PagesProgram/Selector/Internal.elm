module Test.PagesProgram.Selector.Internal exposing
    ( Selector(..)
    , AssertionSelector(..)
    , text, exactText, tag, class, classes, exactClassName, id, value, attribute, containing, all, disabled, checked, selected, style, raw
    , toLabel, toHtmlSelectors, toAssertionSelectors
    , unwrapHtml, unwrapAssertion
    )

{-| Internal representation for `Test.PagesProgram.Selector`. Not part of the
public API. The visual test runner and the main `Test.PagesProgram` module
use these to extract labels and highlight selectors in snapshots.
-}

import Html
import Html.Attributes as Attr
import Test.Html.Selector as HtmlSelector


type Selector
    = Selector String AssertionSelector HtmlSelector.Selector


type AssertionSelector
    = ByText String
    | ByClass String
    | ById_ String
    | ByTag_ String
    | ByValue String
    | ByContaining (List AssertionSelector)
    | ByOther String


text : String -> Selector
text s =
    Selector ("text \"" ++ s ++ "\"") (ByText s) (HtmlSelector.text s)


exactText : String -> Selector
exactText s =
    Selector ("exactText \"" ++ s ++ "\"") (ByText s) (HtmlSelector.exactText s)


tag : String -> Selector
tag s =
    Selector ("<" ++ s ++ ">") (ByTag_ s) (HtmlSelector.tag s)


class : String -> Selector
class s =
    Selector ("." ++ s) (ByClass s) (HtmlSelector.class s)


classes : List String -> Selector
classes cs =
    Selector
        ("classes [" ++ String.join ", " cs ++ "]")
        (ByClass (String.join " " cs))
        (HtmlSelector.classes cs)


exactClassName : String -> Selector
exactClassName s =
    Selector
        ("className=\"" ++ s ++ "\"")
        (ByClass s)
        (HtmlSelector.exactClassName s)


id : String -> Selector
id s =
    Selector ("#" ++ s) (ById_ s) (HtmlSelector.id s)


value : String -> Selector
value s =
    Selector ("value=\"" ++ s ++ "\"") (ByValue s) (HtmlSelector.attribute (Attr.value s))


attribute : String -> Html.Attribute Never -> Selector
attribute label attr =
    Selector label (ByOther label) (HtmlSelector.attribute attr)


containing : List Selector -> Selector
containing selectors =
    Selector
        (":has(" ++ labelsString selectors ++ ")")
        (ByContaining (List.map unwrapAssertion selectors))
        (HtmlSelector.containing (List.map unwrapHtml selectors))


all : List Selector -> Selector
all selectors =
    let
        label : String
        label =
            "all [" ++ labelsString selectors ++ "]"
    in
    Selector
        label
        (ByOther label)
        (HtmlSelector.all (List.map unwrapHtml selectors))


disabled : Bool -> Selector
disabled b =
    let
        label : String
        label =
            if b then
                "[disabled]"

            else
                ":not([disabled])"
    in
    Selector label (ByOther label) (HtmlSelector.disabled b)


checked : Bool -> Selector
checked b =
    let
        label : String
        label =
            if b then
                "[checked]"

            else
                ":not([checked])"
    in
    Selector label (ByOther label) (HtmlSelector.checked b)


selected : Bool -> Selector
selected b =
    let
        label : String
        label =
            if b then
                "[selected]"

            else
                ":not([selected])"
    in
    Selector label (ByOther label) (HtmlSelector.selected b)


style : String -> String -> Selector
style key val =
    let
        label : String
        label =
            "style \"" ++ key ++ ": " ++ val ++ "\""
    in
    Selector label (ByOther label) (HtmlSelector.style key val)


raw : String -> HtmlSelector.Selector -> Selector
raw label sel =
    Selector label (ByOther label) sel


toLabel : List Selector -> String
toLabel selectors =
    selectors
        |> List.map (\(Selector l _ _) -> l)
        |> String.join ", "


toHtmlSelectors : List Selector -> List HtmlSelector.Selector
toHtmlSelectors selectors =
    List.map unwrapHtml selectors


toAssertionSelectors : List Selector -> List AssertionSelector
toAssertionSelectors selectors =
    List.map unwrapAssertion selectors


unwrapHtml : Selector -> HtmlSelector.Selector
unwrapHtml (Selector _ _ sel) =
    sel


unwrapAssertion : Selector -> AssertionSelector
unwrapAssertion (Selector _ a _) =
    a


labelsString : List Selector -> String
labelsString selectors =
    selectors
        |> List.map (\(Selector l _ _) -> l)
        |> String.join ", "
