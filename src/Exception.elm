module Exception exposing (Throwable, Catchable(..), fromString, fromStringWithValue, throw)

{-|

@docs Throwable, Catchable, fromString, fromStringWithValue, throw

-}

import TerminalText


{-| -}
type alias Throwable =
    Catchable ()


{-| -}
type Catchable error
    = Catchable error { title : String, body : List TerminalText.Text }


{-| -}
fromString : String -> Catchable ()
fromString string =
    fromStringWithValue string ()


{-| -}
fromStringWithValue : String -> value -> Catchable value
fromStringWithValue string value =
    Catchable value { title = "Custom Error", body = [ TerminalText.text string ] }


{-| -}
throw : Catchable error -> Catchable ()
throw exception =
    case exception of
        Catchable _ string ->
            Catchable () string
