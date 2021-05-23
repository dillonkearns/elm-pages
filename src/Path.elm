module Path exposing (Path, join, toAbsolute)

{-| Represents the path portion of a URL (not query parameters, fragment, protocol, port, etc.).

This helper lets you combine together path parts without worrying about having too many or too few slashes.
These two examples will result in the same URL, even though the first example has trailing and leading slashes, and the
second does not.

    join [ "/blog/", "/post-1/" ]
        |> Path.toAbsolute
    --> "/blog/post-1"

    join [ "blog", "post-1" ]
        |> Path.toAbsolute
    --> "/blog/post-1"

@docs Path, join, toAbsolute

-}


type Path
    = Path String


join : List String -> Path
join parts =
    parts
        |> List.map normalize
        |> String.join "/"
        |> Path


toAbsolute : Path -> String
toAbsolute (Path path) =
    "/" ++ path


normalize : String -> String
normalize pathPart =
    pathPart
        |> chopEnd "/"
        |> chopStart "/"


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
