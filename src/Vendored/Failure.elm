-- Copied from rtfeldman/node-test-runner : elm/src/Test/Reporter/Console/Format.elm
-- https://github.com/rtfeldman/node-test-runner/blob/master/elm/src/Test/Reporter/Console/Format.elm
-- Published under BSD-3-Clause license, see LICENSE_node-test-runner


module Vendored.Failure exposing (format)

import Test.Runner.Failure exposing (InvalidReason(..), Reason(..))
import Vendored.Highlightable as Highlightable exposing (Highlightable)


format :
    (List (Highlightable String) -> List (Highlightable String) -> ( String, String ))
    -> String
    -> Reason
    -> String
format formatEquality description reason =
    case reason of
        Custom ->
            description

        Equality expected actual ->
            case highlightEqual expected actual of
                Nothing ->
                    verticalBar description expected actual

                Just ( highlightedExpected, highlightedActual ) ->
                    let
                        ( formattedExpected, formattedActual ) =
                            formatEquality highlightedExpected highlightedActual
                    in
                    verticalBar description formattedExpected formattedActual

        Comparison first second ->
            verticalBar description first second

        TODO ->
            description

        Invalid BadDescription ->
            if description == "" then
                "The empty string is not a valid test description."

            else
                "This is an invalid test description: " ++ description

        Invalid _ ->
            description

        ListDiff expected actual ->
            listDiffToString 0
                description
                { expected = expected
                , actual = actual
                }
                { originalExpected = expected
                , originalActual = actual
                }

        CollectionDiff { expected, actual, extra, missing } ->
            let
                extraStr =
                    if List.isEmpty extra then
                        ""

                    else
                        "\nThese keys are extra: "
                            ++ (extra |> String.join ", " |> (\d -> "[ " ++ d ++ " ]"))

                missingStr =
                    if List.isEmpty missing then
                        ""

                    else
                        "\nThese keys are missing: "
                            ++ (missing |> String.join ", " |> (\d -> "[ " ++ d ++ " ]"))
            in
            String.join ""
                [ verticalBar description expected actual
                , "\n"
                , extraStr
                , missingStr
                ]


highlightEqual : String -> String -> Maybe ( List (Highlightable String), List (Highlightable String) )
highlightEqual expected actual =
    if expected == "\"\"" || actual == "\"\"" then
        -- Diffing when one is the empty string looks silly. Don't bother.
        Nothing

    else if isFloat expected && isFloat actual then
        -- Diffing numbers looks silly. Don't bother.
        Nothing

    else
        let
            isHighlighted =
                Highlightable.resolve
                    { fromHighlighted = always True
                    , fromPlain = always False
                    }

            edgeCount highlightedString =
                let
                    highlights =
                        List.map isHighlighted highlightedString
                in
                highlights
                    |> List.map2 Tuple.pair (List.drop 1 highlights)
                    |> List.filter (\( lhs, rhs ) -> lhs /= rhs)
                    |> List.length

            expectedChars =
                String.toList expected

            actualChars =
                String.toList actual

            highlightedExpected =
                Highlightable.diffLists expectedChars actualChars
                    |> List.map (Highlightable.map String.fromChar)

            highlightedActual =
                Highlightable.diffLists actualChars expectedChars
                    |> List.map (Highlightable.map String.fromChar)

            plainCharCount =
                highlightedExpected
                    |> List.filter (not << isHighlighted)
                    |> List.length
        in
        if edgeCount highlightedActual > plainCharCount || edgeCount highlightedExpected > plainCharCount then
            -- Large number of small highlighted blocks. Diff is too messy to be useful.
            Nothing

        else
            Just
                ( highlightedExpected
                , highlightedActual
                )


isFloat : String -> Bool
isFloat str =
    case String.toFloat str of
        Just _ ->
            True

        Nothing ->
            False


listDiffToString :
    Int
    -> String
    -> { expected : List String, actual : List String }
    -> { originalExpected : List String, originalActual : List String }
    -> String
listDiffToString index description { expected, actual } originals =
    case ( expected, actual ) of
        ( [], [] ) ->
            [ "Two lists were unequal previously, yet ended up equal later."
            , "This should never happen!"
            , "Please report this bug to https://github.com/elm-community/elm-test/issues - and include these lists: "
            , "\n"
            , String.join ", " originals.originalExpected
            , "\n"
            , String.join ", " originals.originalActual
            ]
                |> String.join ""

        ( _ :: _, [] ) ->
            verticalBar (description ++ " was shorter than")
                (String.join ", " originals.originalExpected)
                (String.join ", " originals.originalActual)

        ( [], _ :: _ ) ->
            verticalBar (description ++ " was longer than")
                (String.join ", " originals.originalExpected)
                (String.join ", " originals.originalActual)

        ( firstExpected :: restExpected, firstActual :: restActual ) ->
            if firstExpected == firstActual then
                -- They're still the same so far; keep going.
                listDiffToString (index + 1)
                    description
                    { expected = restExpected
                    , actual = restActual
                    }
                    originals

            else
                -- We found elements that differ; fail!
                String.join ""
                    [ verticalBar description
                        (String.join ", " originals.originalExpected)
                        (String.join ", " originals.originalActual)
                    , "\n\nThe first diff is at index "
                    , String.fromInt index
                    , ": it was `"
                    , firstActual
                    , "`, but `"
                    , firstExpected
                    , "` was expected."
                    ]


verticalBar : String -> String -> String -> String
verticalBar comparison expected actual =
    [ actual
    , "╷"
    , "│ " ++ comparison
    , "╵"
    , expected
    ]
        |> String.join "\n"
