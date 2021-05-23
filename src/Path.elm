module Path exposing
    ( Path, join, fromString
    , toAbsolute, toRelative, toSegments
    )

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


## Creating Paths

@docs Path, join, fromString


## Turning Paths to String

@docs toAbsolute, toRelative, toSegments

-}


{-| The path portion of the URL, normalized to ensure that path segments are joined with `/`s in the right places (no doubled up or missing slashes).
-}
type Path
    = Path String


{-| Create a Path from multiple path parts. Each part can either be a single path segment, like `blog`, or a
multi-part path part, like `blog/post-1`.
-}
join : List String -> Path
join parts =
    parts
        |> List.map normalize
        |> String.join "/"
        |> Path


{-| Create a Path from a path String.

    Path.fromString "blog/post-1/"
        |> Path.toAbsolute
        |> Expect.equal "/blog/post-1"

-}
fromString : String -> Path
fromString path =
    path
        |> normalize
        |> Path


{-| -}
toSegments : Path -> List String
toSegments (Path path) =
    path |> String.split "/"


{-| Turn a Path to an absolute URL (with no trailing slash).
-}
toAbsolute : Path -> String
toAbsolute (Path path) =
    "/" ++ path


{-| Turn a Path to a relative URL.
-}
toRelative : Path -> String
toRelative (Path path) =
    path


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
