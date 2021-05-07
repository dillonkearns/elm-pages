module DataSource.Glob exposing
    ( Glob, atLeastOne, extractMatches, fullFilePath, literal, map, oneOf, recursiveWildcard, run, singleFile, succeed, toNonEmptyWithDefault, toPattern, toDataSource, wildcard, zeroOrMore
    , capture, ignore
    , expectUniqueFile, int
    )

{-|

@docs Glob, atLeastOne, extractMatches, fullFilePath, literal, map, oneOf, recursiveWildcard, run, singleFile, succeed, toNonEmptyWithDefault, toPattern, toDataSource, wildcard, zeroOrMore

@docs capture, ignore

-}

import DataSource
import DataSource.Http
import List.Extra
import OptimizedDecoder
import Regex
import Secrets


{-| -}
type Glob a
    = Glob String String (String -> List String -> ( a, List String ))


{-| -}
map : (a -> b) -> Glob a -> Glob b
map mapFn (Glob pattern regex applyCapture) =
    Glob pattern
        regex
        (\fullPath captures ->
            captures
                |> applyCapture fullPath
                |> Tuple.mapFirst mapFn
        )


{-| -}
succeed : constructor -> Glob constructor
succeed constructor =
    Glob "" "" (\_ captures -> ( constructor, captures ))


{-| -}
fullFilePath : Glob String
fullFilePath =
    Glob ""
        ""
        (\fullPath captures ->
            ( fullPath, captures )
        )


{-| -}
wildcard : Glob String
wildcard =
    Glob "*"
        "([^/]*?)"
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


{-| -}
int : Glob Int
int =
    Glob "[0-9]+"
        "([0-9]+?)"
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( String.toInt first |> Maybe.withDefault -1, rest )

                [] ->
                    ( -1, [] )
        )


{-| -}
recursiveWildcard : Glob String
recursiveWildcard =
    Glob "**"
        "(.*?)"
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


{-| -}
zeroOrMore : List String -> Glob (Maybe String)
zeroOrMore matchers =
    Glob
        ("*("
            ++ (matchers |> String.join "|")
            ++ ")"
        )
        ("((?:"
            ++ (matchers |> List.map regexEscaped |> String.join "|")
            ++ ")*)"
        )
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( if first == "" then
                        Nothing

                      else
                        Just first
                    , rest
                    )

                [] ->
                    ( Just "ERROR", [] )
        )


{-| -}
literal : String -> Glob String
literal string =
    Glob string (regexEscaped string) (\_ captures -> ( string, captures ))


regexEscaped : String -> String
regexEscaped stringLiteral =
    --https://stackoverflow.com/a/6969486
    stringLiteral
        |> Regex.replace regexEscapePattern (\match -> "\\" ++ match.match)


regexEscapePattern : Regex.Regex
regexEscapePattern =
    "[.*+?^${}()|[\\]\\\\]"
        |> Regex.fromString
        |> Maybe.withDefault Regex.never


{-| -}
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
ignore : Glob a -> Glob value -> Glob value
ignore (Glob matcherPattern regex1 apply1) (Glob pattern regex2 apply2) =
    Glob
        (pattern ++ matcherPattern)
        (regex2 ++ regex1)
        apply2


{-| -}
capture : Glob a -> Glob (a -> value) -> Glob value
capture (Glob matcherPattern regex1 apply1) (Glob pattern regex2 apply2) =
    Glob
        (pattern ++ matcherPattern)
        (regex2 ++ regex1)
        (\fullPath captures ->
            let
                ( applied1, captured1 ) =
                    captures
                        |> apply1 fullPath

                ( applied2, captured2 ) =
                    captured1
                        |> apply2 fullPath
            in
            ( applied1 |> applied2
            , captured2
            )
        )


{-| -}
oneOf : ( ( String, a ), List ( String, a ) ) -> Glob a
oneOf ( defaultMatch, otherMatchers ) =
    let
        allMatchers =
            defaultMatch :: otherMatchers
    in
    Glob
        ("("
            ++ (allMatchers |> List.map Tuple.first |> String.join "|")
            ++ ")"
        )
        ("("
            ++ String.join "|"
                ((allMatchers |> List.map Tuple.first |> List.map regexEscaped)
                    |> List.map regexEscaped
                )
            ++ ")"
        )
        (\_ captures ->
            case captures of
                match :: rest ->
                    ( allMatchers
                        |> List.Extra.findMap
                            (\( literalString, result ) ->
                                if literalString == match then
                                    Just result

                                else
                                    Nothing
                            )
                        |> Maybe.withDefault (defaultMatch |> Tuple.second)
                    , rest
                    )

                [] ->
                    ( Tuple.second defaultMatch, [] )
        )


{-| -}
atLeastOne : ( ( String, a ), List ( String, a ) ) -> Glob ( a, List a )
atLeastOne ( defaultMatch, otherMatchers ) =
    let
        allMatchers =
            defaultMatch :: otherMatchers
    in
    Glob
        ("+("
            ++ (allMatchers |> List.map Tuple.first |> String.join "|")
            ++ ")"
        )
        ("((?:"
            ++ (allMatchers |> List.map Tuple.first |> List.map regexEscaped |> String.join "|")
            ++ ")+)"
        )
        (\_ captures ->
            case captures of
                match :: rest ->
                    ( --( allMatchers
                      --        |> List.Extra.findMap
                      --            (\( literalString, result ) ->
                      --                if literalString == match then
                      --                    Just result
                      --
                      --                else
                      --                    Nothing
                      --            )
                      --        |> Maybe.withDefault (defaultMatch |> Tuple.second)
                      --  , []
                      --  )
                      extractMatches (defaultMatch |> Tuple.second) allMatchers match
                        |> toNonEmptyWithDefault (defaultMatch |> Tuple.second)
                    , rest
                    )

                [] ->
                    ( ( Tuple.second defaultMatch, [] ), [] )
        )


{-| -}
toNonEmptyWithDefault : a -> List a -> ( a, List a )
toNonEmptyWithDefault default list =
    case list of
        first :: rest ->
            ( first, rest )

        _ ->
            ( default, [] )


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


{-| -}
toDataSource : Glob a -> DataSource.DataSource (List a)
toDataSource glob =
    DataSource.Http.get (Secrets.succeed <| "glob://" ++ toPattern glob)
        (OptimizedDecoder.string
            |> OptimizedDecoder.list
            |> OptimizedDecoder.map
                (\rawGlob -> rawGlob |> List.map (\matchedPath -> run matchedPath glob |> .match))
        )


{-| -}
singleFile : String -> DataSource.DataSource (Maybe String)
singleFile filePath =
    succeed identity
        |> ignore (literal filePath)
        |> capture fullFilePath
        |> toDataSource
        |> DataSource.andThen
            (\globResults ->
                case globResults of
                    [] ->
                        DataSource.succeed Nothing

                    [ single ] ->
                        Just single |> DataSource.succeed

                    multipleResults ->
                        DataSource.fail <| "Unexpected - getSingleFile returned multiple results." ++ (multipleResults |> String.join ", ")
            )


{-| -}
expectUniqueFile : Glob a -> DataSource.DataSource String
expectUniqueFile glob =
    succeed identity
        |> ignore glob
        |> capture fullFilePath
        |> toDataSource
        |> DataSource.andThen
            (\matchingFiles ->
                case matchingFiles |> Debug.log "matchingFiles" of
                    [ file ] ->
                        DataSource.succeed file

                    _ ->
                        DataSource.fail "No files matched."
            )
