module DataSource.Internal.Glob exposing
    ( Glob(..)
    , extractMatches
    , run
    , toPattern
    )

import List.Extra
import Regex


{-| -}
type Glob a
    = Glob String String (String -> List String -> ( a, List String ))


run : String -> Glob a -> { match : a, pattern : String }
run rawInput (Glob pattern regex applyCapture) =
    let
        fullRegex =
            "^" ++ regex ++ "$"

        regexCaptures : List String
        regexCaptures =
            Regex.find parsedRegex rawInput
                |> List.concatMap .submatches
                |> List.map (Maybe.withDefault "")

        parsedRegex =
            Regex.fromString fullRegex |> Maybe.withDefault Regex.never
    in
    { match =
        regexCaptures
            |> List.reverse
            |> applyCapture rawInput
            |> Tuple.first
    , pattern = pattern
    }


{-| -}
toPattern : Glob a -> String
toPattern (Glob pattern regex applyCapture) =
    pattern


{-| -}
extractMatches : a -> List ( String, a ) -> String -> List a
extractMatches defaultValue list string =
    if string == "" then
        []

    else
        let
            ( matchedValue, updatedString ) =
                List.Extra.findMap
                    (\( literalString, value ) ->
                        if string |> String.startsWith literalString then
                            Just ( value, string |> String.dropLeft (String.length literalString) )

                        else
                            Nothing
                    )
                    list
                    |> Maybe.withDefault ( defaultValue, "" )
        in
        matchedValue
            :: extractMatches defaultValue list updatedString
