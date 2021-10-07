module Test.Html.Query exposing
    ( Single, Multiple, fromHtml
    , find, findAll, children, first, index, keep
    , count, contains, has, hasNot, each
    )

{-| Querying HTML structure.

@docs Single, Multiple, fromHtml


## Querying

@docs find, findAll, children, first, index, keep


## Expecting

@docs count, contains, has, hasNot, each

-}

import Expect exposing (Expectation)
import Html exposing (Html)
import Test.Html.Internal.ElmHtml.InternalTypes exposing (ElmHtml)
import Test.Html.Internal.Inert as Inert
import Test.Html.Query.Internal as Internal exposing (QueryError(..), failWithQuery)
import Test.Html.Selector.Internal as Selector exposing (Selector, selectorToString)



{- DESIGN NOTES:

   The reason for having `Query.index` and `Query.first` instead of doing them as
   selectors (which would let you do e.g. `Query.find [ first ]` to get the
   first child, instead of `Query.children [] |> Query.first` like you have to
   do now) is that it's not immediately obvious what a query like this would do:

   Query.findAll [ first, tag "li" ]

   Is that getting the first descendant, and then checking whether it's an <li>?
   Or is it finding the first <li> descendant? (Yes.) Also this is a findAll
   but it's only ever returning a single result despite being typed as a Multiple.

   Arguably `id` could be treated the same way - since you *should* only have
   one id, *should* only ever return one result. However, in that case, it's
   possible that you have multiple IDs - and in that case you actually want the
   test to fail so you find out about the mistake!
-}


{-| A query that expects to find exactly one element.

Contrast with [`Multiple`](#Multiple).

-}
type alias Single msg =
    Internal.Single msg


{-| A query that may find any number of elements, including zero.

Contrast with [`Single`](#Single).

-}
type alias Multiple msg =
    Internal.Multiple msg


{-| Translate a `Html` value into a `Single` query. This is how queries
typically begin.

    import Html
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (text)


    test "Button has the expected text" <|
        \() ->
            Html.button [] [ Html.text "I'm a button!" ]
                |> Query.fromHtml
                |> Query.has [ text "I'm a button!" ]

-}
fromHtml : Html msg -> Single msg
fromHtml html =
    Internal.Single True <|
        case Inert.fromHtml html of
            Ok node ->
                Internal.Query node []

            Err message ->
                Internal.InternalError message



-- TRAVERSAL --


{-| Find the descendant elements which match all the given selectors.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag)
    import Expect


    test "The list has three items" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.findAll [ tag "li" ]
                |> Query.count (Expect.equal 3)

-}
findAll : List Selector -> Single msg -> Multiple msg
findAll selectors (Internal.Single showTrace query) =
    Internal.FindAll selectors
        |> Internal.prependSelector query
        |> Internal.Multiple showTrace


{-| Find the descendant elements of the result of `findAll` which match all the given selectors.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag)
    import Expect


    test "The list has three items" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ a [] [ text "first item" ]]
                    , li [] [ a [] [ text "second item" ]]
                    , li [] [ a [] [ text "third item" ]]
                    , li [] [ button [] [ text "button" ]]
                    ]
                ]
                |> Query.fromHtml
                |> Query.findAll [ tag "li" ]
                |> Query.keep ( tag "a" )
                |> Expect.all
                    [ Query.each (Query.has [ tag "a" ])
                    , Query.first >> Query.has [ text "first item" ]
                    ]

-}
keep : Selector -> Multiple msg -> Multiple msg
keep selector (Internal.Multiple showTrace query) =
    Internal.FindAll [ selector ]
        |> Internal.prependSelector query
        |> Internal.Multiple showTrace


{-| Return the matched element's immediate child elements.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, classes)


    test "The <ul> only has <li> children" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [ class "item"] [ text "first item" ]
                    , li [ class "item selected"] [ text "second item" ]
                    , li [ class "item"] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.find [ class "items" ]
                |> Query.children [ class "selected" ]
                |> Query.count (Expect.equal 1)

-}
children : List Selector -> Single msg -> Multiple msg
children selectors (Internal.Single showTrace query) =
    Internal.Children selectors
        |> Internal.prependSelector query
        |> Internal.Multiple showTrace


{-| Find exactly one descendant element which matches all the given selectors.
If no descendants match, or if more than one matches, the test will fail.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, classes)


    test "The list has both the classes 'items' and 'active'" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.find [ tag "ul" ]
                |> Query.has [ classes [ "items", "active" ] ]

-}
find : List Selector -> Single msg -> Single msg
find selectors (Internal.Single showTrace query) =
    Internal.Find selectors
        |> Internal.prependSelector query
        |> Internal.Single showTrace


{-| Return the first element in a match. If there were no matches, the test
will fail.

`Query.first` is a shorthand for `Query.index 0` - they do the same thing.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, classes)


    test "The first <li> is called 'first item'" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.findAll [ tag "li" ]
                |> Query.first
                |> Query.has [ text "first item" ]

-}
first : Multiple msg -> Single msg
first (Internal.Multiple showTrace query) =
    Internal.First
        |> Internal.prependSelector query
        |> Internal.Single showTrace


{-| Return the element in a match at the given index. For example,
`Query.index 0` would match the first element, and `Query.index 1` would match
the second element.

You can pass negative numbers to get elements from the end - for example, `Query.index -1`
will match the last element, and `Query.index -2` will match the second-to-last.

If the index falls outside the bounds of the match, the test will fail.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, classes)


    test "The second <li> is called 'second item'" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.findAll [ tag "li" ]
                |> Query.index 1
                |> Query.has [ text "second item" ]

-}
index : Int -> Multiple msg -> Single msg
index position (Internal.Multiple showTrace query) =
    Internal.Index position
        |> Internal.prependSelector query
        |> Internal.Single showTrace



-- EXPECTATIONS --


{-| Expect the number of elements matching the query fits the given expectation.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag)
    import Expect


    test "The list has three items" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.findAll [ tag "li" ]
                |> Query.count (Expect.equal 3)

-}
count : (Int -> Expectation) -> Multiple msg -> Expectation
count expect ((Internal.Multiple showTrace query) as multiple) =
    (List.length >> expect >> failWithQuery showTrace "Query.count" query)
        |> Internal.multipleToExpectation multiple


{-| Expect the element to have at least one descendant matching each node in the list.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, classes)


    test "The list has two li: one with the text \"third item\" and \
        another one with \"first item\"" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.contains
                    [ li [] [ text "third item" ]
                    , li [] [ text "first item" ]
                    ]

-}
contains : List (Html msg) -> Single msg -> Expectation
contains expectedHtml (Internal.Single showTrace query) =
    case
        List.map Inert.fromHtml expectedHtml
            |> collectResults
    of
        Ok expectedElmHtml ->
            Internal.contains
                (List.map Inert.toElmHtml expectedElmHtml)
                query
                |> failWithQuery showTrace "Query.contains" query

        Err errors ->
            Expect.fail <|
                String.join "\n" <|
                    List.concat
                        [ [ "Internal Error: failed to decode the virtual dom.  Please report this at <https://github.com/elm-explorations/test/issues>." ]
                        , errors
                        ]


collectResults : List (Result x a) -> Result (List x) (List a)
collectResults listOfResults =
    let
        step : Result (List x) (List a) -> List (Result x a) -> Result (List x) (List a)
        step acc list =
            case ( acc, list ) of
                ( Err errors, [] ) ->
                    Err (List.reverse errors)

                ( Ok values, [] ) ->
                    Ok (List.reverse values)

                ( Err errors, (Err x) :: rest ) ->
                    step (Err (x :: errors)) rest

                ( Ok _, (Err x) :: rest ) ->
                    step (Err [ x ]) rest

                ( Err errors, (Ok _) :: rest ) ->
                    step (Err errors) rest

                ( Ok values, (Ok a) :: rest ) ->
                    step (Ok (a :: values)) rest
    in
    step (Ok []) listOfResults


{-| Expect the element to match all of the given selectors.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, classes)


    test "The list has both the classes 'items' and 'active'" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.find [ tag "ul" ]
                |> Query.has [ tag "ul", classes [ "items", "active" ] ]

-}
has : List Selector -> Single msg -> Expectation
has selectors (Internal.Single showTrace query) =
    Internal.has selectors query
        |> failWithQuery showTrace ("Query.has " ++ Internal.joinAsList selectorToString selectors) query


{-| Expect the element to **not** match all of the given selectors.

    import Html exposing (div)
    import Html.Attributes as Attributes
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, class)


    test "The div element has no progress-bar class" <|
        \() ->
            div [ Attributes.class "button" ] []
                |> Query.fromHtml
                |> Query.find [ tag "div" ]
                |> Query.hasNot [ tag "div", class "progress-bar" ]

-}
hasNot : List Selector -> Single msg -> Expectation
hasNot selectors (Internal.Single showTrace query) =
    let
        queryName =
            "Query.hasNot " ++ Internal.joinAsList selectorToString selectors
    in
    Internal.hasNot selectors query
        |> failWithQuery showTrace queryName query


{-| Expect that a [`Single`](#Single) expectation will hold true for each of the
[`Multiple`](#Multiple) matched elements.

    import Html exposing (div, ul, li)
    import Html.Attributes exposing (class)
    import Test.Html.Query as Query
    import Test exposing (test)
    import Test.Html.Selector exposing (tag, classes)


    test "The list has both the classes 'items' and 'active'" <|
        \() ->
            div []
                [ ul [ class "items active" ]
                    [ li [] [ text "first item" ]
                    , li [] [ text "second item" ]
                    , li [] [ text "third item" ]
                    ]
                ]
                |> Query.fromHtml
                |> Query.findAll [ tag "ul" ]
                |> Query.each
                    (Expect.all
                        [ Query.has [ tag "ul" ]
                        , Query.has [ classes [ "items", "active" ] ]
                        ]
                    )

-}
each : (Single msg -> Expectation) -> Multiple msg -> Expectation
each check (Internal.Multiple showTrace query) =
    Internal.expectAll check query
        |> failWithQuery showTrace "Query.each" query
