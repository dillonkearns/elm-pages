module Glob exposing
    ( Glob, atLeastOne, extractMatches, fullFilePath, literal, map, not, notOneOf, oneOf, recursiveWildcard, run, singleFile, succeed, toNonEmptyWithDefault, toPattern, toStaticHttp, wildcard, zeroOrMore
    , capture, ignore
    )

{-|

@docs Glob, atLeastOne, drop, extractMatches, fullFilePath, keep, literal, map, not, notOneOf, oneOf, recursiveWildcard, run, singleFile, succeed, toNonEmptyWithDefault, toPattern, toStaticHttp, wildcard, zeroOrMore

-}

import DataSource
import DataSource.Http
import List.Extra
import OptimizedDecoder
import Secrets


{-| -}
type Glob a
    = Glob String (String -> List String -> ( a, List String ))


{-| -}
map : (a -> b) -> Glob a -> Glob b
map mapFn (Glob pattern applyCapture) =
    Glob pattern
        (\fullPath captures ->
            captures
                |> applyCapture fullPath
                |> Tuple.mapFirst mapFn
        )


{-| -}
succeed : constructor -> Glob constructor
succeed constructor =
    Glob "" (\_ captures -> ( constructor, captures ))


{-| -}
fullFilePath : Glob String
fullFilePath =
    --Glob "" (\fullPath captures -> ( constructor, captures ))
    --Glob pattern applyCaptures
    Glob ""
        (\fullPath captures ->
            ( fullPath, captures )
        )


{-| -}
wildcard : Glob String
wildcard =
    Glob "*"
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


{-| -}
recursiveWildcard : Glob String
recursiveWildcard =
    Glob "**"
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
    Glob string (\_ captures -> ( string, captures ))


{-| -}
not : String -> Glob String
not string =
    Glob ("!(" ++ string ++ ")")
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


{-| -}
notOneOf : ( String, List String ) -> Glob String
notOneOf ( firstPattern, otherPatterns ) =
    let
        allPatterns =
            firstPattern :: otherPatterns
    in
    Glob
        ("!("
            ++ (allPatterns |> String.join "|")
            ++ ")"
        )
        (\_ captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


{-| -}
run : RawGlob -> Glob a -> { match : a, pattern : String }
run { captures, fullPath } (Glob pattern applyCapture) =
    { match =
        captures
            |> List.reverse
            |> applyCapture fullPath
            |> Tuple.first
    , pattern = pattern
    }


{-| -}
toPattern : Glob a -> String
toPattern (Glob pattern applyCapture) =
    pattern


{-| -}
ignore : Glob a -> Glob value -> Glob value
ignore (Glob matcherPattern apply1) (Glob pattern apply2) =
    Glob
        (pattern ++ matcherPattern)
        apply2


{-| -}
capture : Glob a -> Glob (a -> value) -> Glob value
capture (Glob matcherPattern apply1) (Glob pattern apply2) =
    Glob
        (pattern ++ matcherPattern)
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


type alias RawGlob =
    { captures : List String
    , fullPath : String
    }


{-| -}
toStaticHttp : Glob a -> DataSource.DataSource (List a)
toStaticHttp glob =
    DataSource.Http.get (Secrets.succeed <| "glob://" ++ toPattern glob)
        (OptimizedDecoder.map2 RawGlob
            (OptimizedDecoder.string |> OptimizedDecoder.list |> OptimizedDecoder.field "captures")
            (OptimizedDecoder.field "fullPath" OptimizedDecoder.string)
            |> OptimizedDecoder.list
            |> OptimizedDecoder.map
                (\rawGlob -> rawGlob |> List.map (\inner -> run inner glob |> .match))
        )


{-| -}
singleFile : String -> DataSource.DataSource (Maybe String)
singleFile filePath =
    succeed identity
        |> ignore (literal filePath)
        |> capture fullFilePath
        |> toStaticHttp
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
