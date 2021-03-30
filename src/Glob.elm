module Glob exposing (..)


type Glob a
    = Glob String (List String -> a)


type GlobMatcher
    = Literal String
    | Star


init : constructor -> Glob constructor
init constructor =
    Glob "" (\captures -> constructor)


run : List String -> Glob a -> { match : a, pattern : String }
run captures (Glob pattern applyCapture) =
    { match = applyCapture captures
    , pattern = pattern
    }


toPattern : Glob a -> String
toPattern (Glob pattern applyCapture) =
    pattern


keep : GlobMatcher -> Glob (String -> value) -> Glob value
keep matcher (Glob pattern applyCapture) =
    Glob (pattern ++ matcherToPattern matcher)
        (case matcher of
            Literal literalString ->
                continueNonCapturing literalString applyCapture

            Star ->
                popCapture applyCapture
        )


matcherToPattern : GlobMatcher -> String
matcherToPattern matcher =
    case matcher of
        Literal literalString ->
            literalString

        Star ->
            "*"


continueNonCapturing : String -> (List String -> (String -> value)) -> (List String -> value)
continueNonCapturing hardcodedCaptureValue applyCapture =
    \captures ->
        applyCapture captures hardcodedCaptureValue


popCapture : (List String -> (String -> value)) -> (List String -> value)
popCapture applyCapture =
    \captures ->
        case captures of
            first :: rest ->
                applyCapture rest first

            [] ->
                applyCapture [] "ERROR"


drop : GlobMatcher -> Glob a -> Glob a
drop matcher (Glob pattern applyCapture) =
    Glob (pattern ++ matcherToPattern matcher)
        (\captures ->
            case matcher of
                Literal literalString ->
                    applyCapture captures

                Star ->
                    applyCapture captures
        )


literal : String -> GlobMatcher
literal string =
    Literal string


star : GlobMatcher
star =
    Star
