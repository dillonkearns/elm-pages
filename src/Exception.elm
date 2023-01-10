module Exception exposing (Throwable, Exception(..), fromString, fromStringWithValue, throw)

{-|

@docs Throwable, Exception, fromString, fromStringWithValue, throw

-}


{-| -}
type alias Throwable =
    Exception ()


{-| -}
type Exception error
    = Exception error { title : String, body : String }


{-| -}
fromString : String -> Exception ()
fromString string =
    fromStringWithValue string ()


{-| -}
fromStringWithValue : String -> value -> Exception value
fromStringWithValue string value =
    Exception value { title = "Custom Error", body = string }


{-| -}
throw : Exception error -> Exception ()
throw exception =
    case exception of
        Exception _ string ->
            Exception () string
