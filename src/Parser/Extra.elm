module Parser.Extra exposing (deadEndsToString)

{-| [No implementation for deadEndsToString · Issue #9 · elm/parser](https://github.com/elm/parser/issues/9)
-}

import Parser exposing (DeadEnd, Problem(..))


deadEndsToString : List DeadEnd -> String
deadEndsToString deadEnds =
    String.join "\n" (List.map deadEndToString deadEnds)


deadEndToString : DeadEnd -> String
deadEndToString deadEnd =
    problemToString deadEnd.problem
        ++ " at "
        ++ deadEndToRowColString deadEnd


problemToString : Problem -> String
problemToString prob =
    case prob of
        Expecting s ->
            "Expecting " ++ s

        ExpectingInt ->
            "Expecting Int"

        ExpectingHex ->
            "Expecting Hex"

        ExpectingOctal ->
            "Expecting Octal"

        ExpectingBinary ->
            "Expecting Binary"

        ExpectingFloat ->
            "Expecting Float"

        ExpectingNumber ->
            "Expecting Number"

        ExpectingVariable ->
            "Expecting Variable"

        ExpectingSymbol s ->
            "Expecting Symbol " ++ s

        ExpectingKeyword s ->
            "Expecting Keyword " ++ s

        ExpectingEnd ->
            "Expecting End"

        UnexpectedChar ->
            "Unexpected Char"

        Problem s ->
            "Problem: " ++ s

        BadRepeat ->
            "Bad Repeat"


deadEndToRowColString : DeadEnd -> String
deadEndToRowColString deadEnd =
    "row " ++ String.fromInt deadEnd.row ++ ", " ++ "col " ++ String.fromInt deadEnd.col
