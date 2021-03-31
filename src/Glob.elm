module Glob exposing (..)

import List.Extra


type Glob a
    = Glob String (List String -> a)


type NewGlob a
    = NewGlob String (List String -> ( a, List String ))


type GlobMatcher a
    = GlobMatcher String (CaptureToValue a)


type CaptureToValue a
    = Hardcoded a
    | Dynamic (String -> a)


map : (a -> b) -> NewGlob a -> NewGlob b
map mapFn (NewGlob pattern applyCapture) =
    NewGlob pattern
        (\captures ->
            captures
                |> applyCapture
                |> Tuple.mapFirst mapFn
        )


succeed : constructor -> Glob constructor
succeed constructor =
    Glob "" (\captures -> constructor)


succeed2 : constructor -> NewGlob constructor
succeed2 constructor =
    NewGlob "" (\captures -> ( constructor, captures ))


star2 : NewGlob String
star2 =
    NewGlob "*"
        (\captures ->
            case captures of
                first :: rest ->
                    ( first, rest )

                --applyCapture rest (toValueFn first)
                [] ->
                    ( "ERROR", [] )
         --applyCapture [] (toValueFn "ERROR")
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


toPattern : Glob a -> String
toPattern (Glob pattern applyCapture) =
    pattern


keep : GlobMatcher a -> Glob (a -> value) -> Glob value
keep (GlobMatcher matcherPattern toValue) (Glob pattern applyCapture) =
    Glob (pattern ++ matcherPattern)
        (case toValue of
            Hardcoded value ->
                continueNonCapturing value applyCapture

            Dynamic toValueFn ->
                popCapture toValueFn applyCapture
        )


continueNonCapturing : a -> (List String -> (a -> value)) -> (List String -> value)
continueNonCapturing hardcodedCaptureValue applyCapture =
    \captures ->
        applyCapture captures hardcodedCaptureValue


popCapture : (String -> a) -> (List String -> (a -> value)) -> (List String -> value)
popCapture toValueFn applyCapture =
    \captures ->
        case captures of
            first :: rest ->
                applyCapture rest (toValueFn first)

            [] ->
                applyCapture [] (toValueFn "ERROR")


drop2 : NewGlob a -> NewGlob value -> NewGlob value
drop2 (NewGlob matcherPattern apply1) (NewGlob pattern apply2) =
    NewGlob
        (pattern ++ matcherPattern)
        apply2



--keep : GlobMatcher a -> Glob (a -> value) -> Glob value


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


drop : GlobMatcher a -> Glob value -> Glob value
drop (GlobMatcher matcherPattern toValue) (Glob pattern applyCapture) =
    Glob
        (pattern ++ matcherPattern)
        (case toValue of
            Hardcoded value ->
                applyCapture

            Dynamic toValueFn ->
                \captures ->
                    applyCapture (captures |> List.drop 1)
        )


oneOf : ( ( String, a ), List ( String, a ) ) -> GlobMatcher a
oneOf ( defaultMatch, otherMatchers ) =
    let
        allMatchers =
            defaultMatch :: otherMatchers
    in
    GlobMatcher
        ("{"
            ++ (allMatchers |> List.map Tuple.first |> String.join ",")
            ++ "}"
        )
        (Dynamic
            (\match ->
                allMatchers
                    |> List.Extra.findMap
                        (\( literalString, result ) ->
                            if literalString == match then
                                Just result

                            else
                                Nothing
                        )
                    |> Maybe.withDefault (defaultMatch |> Tuple.second)
            )
        )


zeroOrMore : List String -> GlobMatcher (Maybe String)
zeroOrMore matchers =
    GlobMatcher
        ("*("
            ++ (matchers |> String.join "|")
            ++ ")"
        )
        (Dynamic
            (\s ->
                if s == "" then
                    Nothing

                else
                    Just s
            )
        )


literal : String -> GlobMatcher String
literal string =
    GlobMatcher string (Hardcoded string)


star : GlobMatcher String
star =
    GlobMatcher "*" (Dynamic identity)
