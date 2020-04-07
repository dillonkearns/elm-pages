module Pages.Internal.String exposing (..)

{-| Remove a piece from the beginning of a string until it's not there anymore.

    >>> chopStart "{" "{{{<-"
    "<-"

-}


chopStart : String -> String -> String
chopStart needle string =
    if String.startsWith needle string then
        string
            |> String.dropLeft (String.length needle)
            |> chopStart needle

    else
        string


{-| Remove a piece from the end of a string until it's not there anymore.

    >>> chopEnd "}" "->}}}"
    "->"

-}
chopEnd : String -> String -> String
chopEnd needle string =
    if String.endsWith needle string then
        string
            |> String.dropRight (String.length needle)
            |> chopEnd needle

    else
        string


{-| Removes `/` characters from both ends of a string.
-}
chopForwardSlashes : String -> String
chopForwardSlashes =
    chopStart "/" >> chopEnd "/"
