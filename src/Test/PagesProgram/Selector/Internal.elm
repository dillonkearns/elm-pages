module Test.PagesProgram.Selector.Internal exposing
    ( Selector(..)
    , AssertionSelector(..)
    , text, tag, class, id, value, attribute, containing, disabled, raw
    , toLabel, toHtmlSelectors, toAssertionSelectors
    , unwrapHtml, unwrapAssertion
    )

{-| Internal representation for `Test.PagesProgram.Selector`. Not part of the
public API. The visual test runner and the main `Test.PagesProgram` module
use these to extract labels and highlight selectors in snapshots.
-}

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


tag : String -> Selector
tag s =
    Selector ("<" ++ s ++ ">") (ByTag_ s) (HtmlSelector.tag s)


class : String -> Selector
class s =
    Selector ("." ++ s) (ByClass s) (HtmlSelector.class s)


id : String -> Selector
id s =
    Selector ("#" ++ s) (ById_ s) (HtmlSelector.id s)


value : String -> Selector
value s =
    Selector ("value=\"" ++ s ++ "\"") (ByValue s) (HtmlSelector.attribute (Attr.value s))


attribute : String -> HtmlSelector.Selector -> Selector
attribute label sel =
    Selector label (ByOther label) sel


containing : List Selector -> Selector
containing selectors =
    Selector
        (":has(" ++ labelsString selectors ++ ")")
        (ByContaining (List.map unwrapAssertion selectors))
        (HtmlSelector.containing (List.map unwrapHtml selectors))


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


raw : String -> HtmlSelector.Selector -> Selector
raw label sel =
    Selector label (ByOther label) sel


toLabel : List Selector -> String
toLabel selectors =
    selectors
        |> List.map (\(Selector label _ _) -> label)
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
        |> List.map (\(Selector label _ _) -> label)
        |> String.join ", "
