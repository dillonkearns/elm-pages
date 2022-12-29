module Exception exposing (Throwable, Catchable(..), fromString, fromStringWithValue, throw)

{-|

@docs Throwable, Catchable, fromString, fromStringWithValue, throw

-}


{-| -}
type alias Throwable =
    Catchable ()


{-| -}
type Catchable error
    = Catchable error String


{-| -}
fromString : String -> Catchable ()
fromString string =
    Catchable () string


{-| -}
fromStringWithValue : String -> value -> Catchable value
fromStringWithValue string value =
    Catchable value string


{-| -}
throw : Catchable error -> Catchable ()
throw exception =
    case exception of
        Catchable error string ->
            Catchable () string
