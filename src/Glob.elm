module Glob exposing (..)

import List.Extra
import OptimizedDecoder
import Pages.StaticHttp as StaticHttp
import Secrets


type Glob a
    = Glob String (List String -> ( a, List String ))


map : (a -> b) -> Glob a -> Glob b
map mapFn (Glob pattern applyCapture) =
    Glob pattern
        (\captures ->
            captures
                |> applyCapture
                |> Tuple.mapFirst mapFn
        )


succeed : constructor -> Glob constructor
succeed constructor =
    Glob "" (\captures -> ( constructor, captures ))


wildcard : Glob String
wildcard =
    Glob "*"
        (\captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


recursiveWildcard : Glob String
recursiveWildcard =
    Glob "**"
        (\captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


zeroOrMore : List String -> Glob (Maybe String)
zeroOrMore matchers =
    Glob
        ("*("
            ++ (matchers |> String.join "|")
            ++ ")"
        )
        (\captures ->
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


literal : String -> Glob String
literal string =
    Glob string (\captures -> ( string, captures ))


not : String -> Glob String
not string =
    Glob ("!(" ++ string ++ ")")
        (\captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


run : List String -> Glob a -> { match : a, pattern : String }
run captures (Glob pattern applyCapture) =
    { match =
        captures
            |> List.reverse
            |> applyCapture
            |> Tuple.first
    , pattern = pattern
    }


toPattern : Glob a -> String
toPattern (Glob pattern applyCapture) =
    pattern


drop : Glob a -> Glob value -> Glob value
drop (Glob matcherPattern apply1) (Glob pattern apply2) =
    Glob
        (pattern ++ matcherPattern)
        apply2


keep : Glob a -> Glob (a -> value) -> Glob value
keep (Glob matcherPattern apply1) (Glob pattern apply2) =
    Glob
        (pattern ++ matcherPattern)
        (\captures ->
            let
                ( applied1, captured1 ) =
                    captures
                        |> apply1

                ( applied2, captured2 ) =
                    captured1
                        |> apply2
            in
            ( applied1 |> applied2
            , captured2
            )
        )


oneOf : ( ( String, a ), List ( String, a ) ) -> Glob a
oneOf ( defaultMatch, otherMatchers ) =
    let
        allMatchers =
            defaultMatch :: otherMatchers
    in
    Glob
        ("{"
            ++ (allMatchers |> List.map Tuple.first |> String.join ",")
            ++ "}"
        )
        (\captures ->
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


toStaticHttp : Glob a -> StaticHttp.Request (List a)
toStaticHttp glob =
    StaticHttp.get (Secrets.succeed <| "glob://" ++ toPattern glob)
        (OptimizedDecoder.string
            |> OptimizedDecoder.list
            |> OptimizedDecoder.list
            |> OptimizedDecoder.map
                (\appliedList -> appliedList |> List.map (\inner -> run inner glob |> .match))
        )
