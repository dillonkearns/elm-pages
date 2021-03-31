module Glob exposing (..)

import List.Extra


type Glob a
    = Glob String (List String -> a)


type NewGlob a
    = NewGlob String (List String -> ( a, List String ))


map : (a -> b) -> NewGlob a -> NewGlob b
map mapFn (NewGlob pattern applyCapture) =
    NewGlob pattern
        (\captures ->
            captures
                |> applyCapture
                |> Tuple.mapFirst mapFn
        )


succeed : constructor -> NewGlob constructor
succeed constructor =
    NewGlob "" (\captures -> ( constructor, captures ))


star : NewGlob String
star =
    NewGlob "*"
        (\captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                [] ->
                    ( "ERROR", [] )
        )


zeroOrMore : List String -> NewGlob (Maybe String)
zeroOrMore matchers =
    NewGlob
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


literal2 : String -> NewGlob String
literal2 string =
    NewGlob string (\captures -> ( string, captures ))


runNew : List String -> NewGlob a -> { match : a, pattern : String }
runNew captures (NewGlob pattern applyCapture) =
    { match =
        captures
            |> List.reverse
            |> applyCapture
            |> Tuple.first
    , pattern = pattern
    }


run : List String -> Glob a -> { match : a, pattern : String }
run captures (Glob pattern applyCapture) =
    { match =
        captures
            |> List.reverse
            |> applyCapture
    , pattern = pattern
    }


toPattern : NewGlob a -> String
toPattern (NewGlob pattern applyCapture) =
    pattern


drop2 : NewGlob a -> NewGlob value -> NewGlob value
drop2 (NewGlob matcherPattern apply1) (NewGlob pattern apply2) =
    NewGlob
        (pattern ++ matcherPattern)
        apply2


keep2 : NewGlob a -> NewGlob (a -> value) -> NewGlob value
keep2 (NewGlob matcherPattern apply1) (NewGlob pattern apply2) =
    NewGlob
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


oneOf2 : ( ( String, a ), List ( String, a ) ) -> NewGlob a
oneOf2 ( defaultMatch, otherMatchers ) =
    let
        allMatchers =
            defaultMatch :: otherMatchers
    in
    NewGlob
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
