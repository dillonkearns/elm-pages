module Glob exposing (..)

import List.Extra


type Glob a
    = Glob String (List String -> a)


type GlobMatcher a
    = GlobMatcher String (CaptureToValue a)


type CaptureToValue a
    = Hardcoded a
    | Dynamic (String -> a)


init : constructor -> Glob constructor
init constructor =
    Glob "" (\captures -> constructor)


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
        let
            _ =
                Debug.log "pop" captures
        in
        case captures of
            first :: rest ->
                applyCapture rest (toValueFn first)

            [] ->
                --applyCapture [] (toValueFn "ERROR")
                Debug.todo "Ran out of items"


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
                            if
                                (literalString |> Debug.log "lhs")
                                    == (match |> Debug.log "rhs")
                            then
                                Just result

                            else
                                Nothing
                        )
                    |> Maybe.withDefault (defaultMatch |> Tuple.second)
            )
        )


literal : String -> GlobMatcher String
literal string =
    GlobMatcher string (Hardcoded string)


star : GlobMatcher String
star =
    GlobMatcher "*" (Dynamic identity)
