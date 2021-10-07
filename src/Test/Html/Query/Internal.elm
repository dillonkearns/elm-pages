module Test.Html.Query.Internal exposing (Multiple(..), Query(..), QueryError(..), SelectorQuery(..), Single(..), addQueryFromHtmlLine, baseIndentation, contains, expectAll, expectAllHelp, failWithQuery, getChildren, getElementAt, getElementAtHelp, getHtmlContext, has, hasNot, isElement, joinAsList, missingDescendants, multipleToExpectation, prefixOutputLine, prependSelector, prettyPrint, printIndented, queryErrorToString, showSelectorOutcome, showSelectorOutcomeInverse, toLines, toLinesHelp, toOutputLine, traverse, traverseSelector, traverseSelectors, verifySingle, withHtmlContext)

import Expect exposing (Expectation)
import Test.Html.Descendant as Descendant
import Test.Html.Internal.ElmHtml.InternalTypes exposing (ElmHtml(..))
import Test.Html.Internal.ElmHtml.ToString exposing (nodeToStringWithOptions)
import Test.Html.Internal.Inert as Inert exposing (Node)
import Test.Html.Selector.Internal as InternalSelector exposing (Selector, selectorToString)
import Test.Runner


{-| Note: the selectors are stored in reverse order for better prepending perf.
-}
type Query msg
    = Query (Inert.Node msg) (List SelectorQuery)
    | InternalError String


type SelectorQuery
    = Find (List Selector)
    | FindAll (List Selector)
    | Children (List Selector)
      -- First and Index are separate so we can report Query.first in error messages
    | First
    | Index Int


{-| The Bool is `showTrace` - whether to show the Query.fromHtml trace at
the beginning of the error message.

We need to track this so that Query.each can turn it off. Otherwise you get
fromHtml printed twice - once at the very top, then again for the nested
expectation that Query.each delegated to.

-}
type Single msg
    = Single Bool (Query msg)


{-| The Bool is `showTrace` - see `Single` for more info.
-}
type Multiple msg
    = Multiple Bool (Query msg)


type QueryError
    = NoResultsForSingle String
    | MultipleResultsForSingle String Int
    | OtherInternalError String


toLines : String -> Query msg -> String -> List String
toLines expectationFailure query queryName =
    case query of
        Query node selectors ->
            toLinesHelp expectationFailure [ Inert.toElmHtml node ] (List.reverse selectors) queryName []
                |> List.reverse

        InternalError message ->
            [ "Internal Error: failed to decode the virtual dom.  Please report this at <https://github.com/elm-explorations/test/issues>"
            , message
            ]


prettyPrint : ElmHtml msg -> String
prettyPrint =
    nodeToStringWithOptions { indent = 4, newLines = True }


toOutputLine : Query msg -> String
toOutputLine query =
    case query of
        Query node _ ->
            prettyPrint (Inert.toElmHtml node)

        InternalError message ->
            "Internal Error: failed to decode the virtual dom.  Please report this at <https://github.com/elm-explorations/test/issues>.  "
                ++ message


toLinesHelp : String -> List (ElmHtml msg) -> List SelectorQuery -> String -> List String -> List String
toLinesHelp expectationFailure elmHtmlList selectorQueries queryName results =
    let
        bailOut result =
            -- Bail out early so the last error message the user
            -- sees is Query.find rather than something like
            -- Query.has, to reflect how we didn't make it that far.
            String.join "\n\n\n✗ " [ result, expectationFailure ] :: results

        recurse newElmHtmlList rest result =
            toLinesHelp
                expectationFailure
                newElmHtmlList
                rest
                queryName
                (result :: results)
    in
    case selectorQueries of
        [] ->
            String.join "\n\n" [ queryName, expectationFailure ] :: results

        selectorQuery :: rest ->
            case selectorQuery of
                FindAll selectors ->
                    let
                        elements =
                            elmHtmlList
                                |> List.concatMap getChildren
                                |> InternalSelector.queryAll selectors
                    in
                    ("Query.findAll " ++ joinAsList selectorToString selectors)
                        |> withHtmlContext (getHtmlContext elements)
                        |> recurse elements rest

                Find selectors ->
                    let
                        elements =
                            elmHtmlList
                                |> List.concatMap getChildren
                                |> InternalSelector.queryAll selectors

                        result =
                            ("Query.find " ++ joinAsList selectorToString selectors)
                                |> withHtmlContext (getHtmlContext elements)
                    in
                    if List.length elements == 1 then
                        recurse elements rest result

                    else
                        bailOut result

                Children selectors ->
                    let
                        elements =
                            elmHtmlList
                                |> List.concatMap getChildren
                                |> InternalSelector.queryAllChildren selectors
                    in
                    ("Query.children " ++ joinAsList selectorToString selectors)
                        |> withHtmlContext (getHtmlContext elements)
                        |> recurse elements rest

                First ->
                    let
                        elements =
                            elmHtmlList
                                |> List.head
                                |> Maybe.map (\elem -> [ elem ])
                                |> Maybe.withDefault []

                        result =
                            "Query.first"
                                |> withHtmlContext (getHtmlContext elements)
                    in
                    if List.length elements == 1 then
                        recurse elements rest result

                    else
                        bailOut result

                Index index ->
                    let
                        elements =
                            elmHtmlList
                                |> getElementAt index

                        result =
                            ("Query.index " ++ String.fromInt index)
                                |> withHtmlContext (getHtmlContext elements)
                    in
                    if List.length elements == 1 then
                        recurse elements rest result

                    else
                        bailOut result


withHtmlContext : String -> String -> String
withHtmlContext htmlStr str =
    String.join "\n\n" [ str, htmlStr ]


getHtmlContext : List (ElmHtml msg) -> String
getHtmlContext elmHtmlList =
    if List.isEmpty elmHtmlList then
        "0 matches found for this query."

    else
        let
            maxDigits =
                elmHtmlList
                    |> List.length
                    |> String.fromInt
                    |> String.length
        in
        elmHtmlList
            |> List.indexedMap (printIndented maxDigits)
            |> String.join "\n\n"


joinAsList : (a -> String) -> List a -> String
joinAsList toStr list =
    if List.isEmpty list then
        "[]"

    else
        "[ " ++ String.join ", " (List.map toStr list) ++ " ]"


printIndented : Int -> Int -> ElmHtml msg -> String
printIndented maxDigits index elmHtml =
    let
        caption =
            (String.fromInt (index + 1) ++ ")")
                |> String.padRight (maxDigits + 3) ' '
                |> String.append baseIndentation

        indentation =
            String.repeat (String.length caption) " "
    in
    case String.split "\n" (prettyPrint elmHtml) of
        [] ->
            ""

        first :: rest ->
            rest
                |> List.map (String.append indentation)
                |> (::) (caption ++ first)
                |> String.join "\n"


baseIndentation : String
baseIndentation =
    "    "


prependSelector : Query msg -> SelectorQuery -> Query msg
prependSelector query selector =
    case query of
        Query node selectors ->
            Query node (selector :: selectors)

        InternalError message ->
            InternalError message


{-| This is a more efficient implementation of the following:

    list
        |> Array.fromList
        |> Array.get index
        |> Maybe.map (\elem -> [ elem ])
        |> Maybe.withDefault []

It also supports negative indeces, e.g. passing -1 for an index
gets you the last element.

-}
getElementAt : Int -> List a -> List a
getElementAt index list =
    let
        length =
            List.length list
    in
    if
        -- Avoid attempting % 0
        (length == 0)
            -- don't wrap around if index is too high
            || (index >= length)
            -- don't wrap around if index is too low
            || (index < 0 && abs index > length)
    then
        []

    else
        -- Support wraparound, e.g. passing -1 to get the last element.
        getElementAtHelp (modBy length index) list


getElementAtHelp : Int -> List a -> List a
getElementAtHelp index list =
    case list of
        [] ->
            []

        first :: rest ->
            if index == 0 then
                [ first ]

            else
                getElementAtHelp (index - 1) rest


traverse : Query msg -> Result QueryError (List (ElmHtml msg))
traverse query =
    case query of
        Query node selectorQueries ->
            traverseSelectors selectorQueries [ Inert.toElmHtml node ]

        InternalError message ->
            Err (OtherInternalError message)


traverseSelectors : List SelectorQuery -> List (ElmHtml msg) -> Result QueryError (List (ElmHtml msg))
traverseSelectors selectorQueries elmHtmlList =
    List.foldr
        (traverseSelector >> Result.andThen)
        (Ok elmHtmlList)
        selectorQueries


traverseSelector : SelectorQuery -> List (ElmHtml msg) -> Result QueryError (List (ElmHtml msg))
traverseSelector selectorQuery elmHtmlList =
    case selectorQuery of
        Find selectors ->
            elmHtmlList
                |> List.concatMap getChildren
                |> InternalSelector.queryAll selectors
                |> verifySingle "Query.find"
                |> Result.map (\elem -> [ elem ])

        FindAll selectors ->
            elmHtmlList
                |> List.concatMap getChildren
                |> InternalSelector.queryAll selectors
                |> Ok

        Children selectors ->
            elmHtmlList
                |> List.concatMap getChildren
                |> InternalSelector.queryAllChildren selectors
                |> Ok

        First ->
            elmHtmlList
                |> List.head
                |> Maybe.map (\elem -> Ok [ elem ])
                |> Maybe.withDefault (Err (NoResultsForSingle "Query.first"))

        Index index ->
            let
                elements =
                    elmHtmlList
                        |> getElementAt index
            in
            if List.length elements == 1 then
                Ok elements

            else
                Err (NoResultsForSingle ("Query.index " ++ String.fromInt index))


getChildren : ElmHtml msg -> List (ElmHtml msg)
getChildren elmHtml =
    case elmHtml of
        NodeEntry { children } ->
            children

        _ ->
            []


isElement : ElmHtml msg -> Bool
isElement elmHtml =
    case elmHtml of
        NodeEntry _ ->
            True

        _ ->
            False


verifySingle : String -> List a -> Result QueryError a
verifySingle queryName list =
    case list of
        [] ->
            Err (NoResultsForSingle queryName)

        singleton :: [] ->
            Ok singleton

        multiples ->
            Err (MultipleResultsForSingle queryName (List.length multiples))


expectAll : (Single msg -> Expectation) -> Query msg -> Expectation
expectAll check query =
    case traverse query of
        Ok list ->
            expectAllHelp 0 check list

        Err error ->
            Expect.fail (queryErrorToString query error)


expectAllHelp : Int -> (Single msg -> Expectation) -> List (ElmHtml msg) -> Expectation
expectAllHelp successes check list =
    case list of
        [] ->
            Expect.pass

        elmHtml :: rest ->
            let
                expectation =
                    Query (Inert.fromElmHtml elmHtml) []
                        |> Single False
                        |> check
            in
            case Test.Runner.getFailureReason expectation of
                Just { given, description } ->
                    let
                        prefix =
                            if successes > 0 then
                                "Element #" ++ String.fromInt (successes + 1) ++ " failed this test:"

                            else
                                "The first element failed this test:"
                    in
                    [ prefix, description ]
                        |> String.join "\n\n"
                        |> Expect.fail

                Nothing ->
                    expectAllHelp (successes + 1) check rest


multipleToExpectation : Multiple msg -> (List (ElmHtml msg) -> Expectation) -> Expectation
multipleToExpectation (Multiple _ query) check =
    case traverse query of
        Ok list ->
            check list

        Err error ->
            Expect.fail (queryErrorToString query error)


queryErrorToString : Query msg -> QueryError -> String
queryErrorToString query error =
    case error of
        NoResultsForSingle queryName ->
            queryName ++ " always expects to find 1 element, but it found 0 instead."

        MultipleResultsForSingle queryName resultCount ->
            queryName
                ++ " always expects to find 1 element, but it found "
                ++ String.fromInt resultCount
                ++ " instead.\n\n\nHINT: If you actually expected "
                ++ String.fromInt resultCount
                ++ " elements, use Query.findAll instead of Query.find."

        OtherInternalError message ->
            "Internal Error: failed to decode the virtual dom.  Please report this at <https://github.com/elm-explorations/test/issues>.  "
                ++ message


contains : List (ElmHtml msg) -> Query msg -> Expectation
contains expectedDescendants query =
    case traverse query of
        Ok elmHtmlList ->
            let
                missing =
                    missingDescendants elmHtmlList expectedDescendants

                prettyPrintSections missingDescendantsList =
                    String.join
                        "\n\n---------------------------------------------\n\n"
                        (List.indexedMap
                            (\index descendant -> printIndented 3 index descendant)
                            missingDescendantsList
                        )
            in
            if List.isEmpty missing then
                Expect.pass

            else
                Expect.fail
                    (String.join ""
                        [ "\t✗ /"
                        , String.fromInt <| List.length missing
                        , "\\ missing descendants: \n\n"
                        , prettyPrintSections missing
                        ]
                    )

        Err error ->
            Expect.fail (queryErrorToString query error)


missingDescendants : List (ElmHtml msg) -> List (ElmHtml msg) -> List (ElmHtml msg)
missingDescendants elmHtmlList expected =
    let
        isMissing =
            \expectedDescendant ->
                not <| Descendant.isDescendant elmHtmlList expectedDescendant
    in
    List.filter isMissing expected


has : List Selector -> Query msg -> Expectation
has selectors query =
    case traverse query of
        Ok elmHtmlList ->
            if InternalSelector.hasAll selectors elmHtmlList then
                Expect.pass

            else
                selectors
                    |> List.map (showSelectorOutcome elmHtmlList)
                    |> String.join "\n"
                    |> Expect.fail

        Err error ->
            Expect.fail (queryErrorToString query error)


hasNot : List Selector -> Query msg -> Expectation
hasNot selectors query =
    case traverse query of
        Ok [] ->
            Expect.pass

        Ok elmHtmlList ->
            case InternalSelector.queryAll selectors elmHtmlList of
                [] ->
                    Expect.pass

                _ ->
                    selectors
                        |> List.map (showSelectorOutcomeInverse elmHtmlList)
                        |> String.join "\n"
                        |> Expect.fail

        Err error ->
            Expect.pass


showSelectorOutcome : List (ElmHtml msg) -> Selector -> String
showSelectorOutcome elmHtmlList selector =
    let
        outcome =
            case InternalSelector.queryAll [ selector ] elmHtmlList of
                [] ->
                    "✗"

                _ ->
                    "✓"
    in
    String.join " " [ outcome, "has", selectorToString selector ]


showSelectorOutcomeInverse : List (ElmHtml msg) -> Selector -> String
showSelectorOutcomeInverse elmHtmlList selector =
    let
        outcome =
            case InternalSelector.queryAll [ selector ] elmHtmlList of
                [] ->
                    "✓"

                _ ->
                    "✗"
    in
    String.join " " [ outcome, "has not", selectorToString selector ]



-- HELPERS --


failWithQuery : Bool -> String -> Query msg -> Expectation -> Expectation
failWithQuery showTrace queryName query expectation =
    case Test.Runner.getFailureReason expectation of
        Just { given, description } ->
            let
                lines =
                    toLines description query queryName
                        |> List.map prefixOutputLine

                tracedLines =
                    if showTrace then
                        addQueryFromHtmlLine query :: lines

                    else
                        lines
            in
            tracedLines
                |> String.join "\n\n\n"
                |> Expect.fail

        Nothing ->
            expectation


addQueryFromHtmlLine : Query msg -> String
addQueryFromHtmlLine query =
    String.join "\n\n"
        [ prefixOutputLine "Query.fromHtml"
        , toOutputLine query
            |> String.split "\n"
            |> List.map ((++) baseIndentation)
            |> String.join "\n"
        ]


prefixOutputLine : String -> String
prefixOutputLine =
    (++) "▼ "
