module UrlPath exposing
    ( UrlPath, join, fromString
    , toAbsolute, toRelative, toSegments
    )

{-| Represents the path portion of a URL (not query parameters, fragment, protocol, port, etc.).

This helper lets you combine together path parts without worrying about having too many or too few slashes.
These two examples will result in the same URL, even though the first example has trailing and leading slashes, and the
second does not.

    UrlPath.join [ "/blog/", "/post-1/" ]
        |> UrlPath.toAbsolute
    --> "/blog/post-1"

    UrlPath.join [ "blog", "post-1" ]
        |> UrlPath.toAbsolute
    --> "/blog/post-1"

We can also safely join Strings that include multiple path parts, a single path part per string, or a mix of the two:

    UrlPath.join [ "/articles/archive/", "1977", "06", "10", "post-1" ]
        |> UrlPath.toAbsolute
    --> "/articles/archive/1977/06/10/post-1"


## Creating UrlPaths

@docs UrlPath, join, fromString


## Turning UrlPaths to String

@docs toAbsolute, toRelative, toSegments

-}

import Pages.Internal.String exposing (chopEnd, chopStart)


{-| The path portion of the URL, normalized to ensure that path segments are joined with `/`s in the right places (no doubled up or missing slashes).
-}
type alias UrlPath =
    List String


{-| Turn a Path to a relative URL.
-}
join : UrlPath -> UrlPath
join parts =
    parts
        |> List.filter (\segment -> segment /= "/")
        |> List.map normalize


{-| Turn a UrlPath to a relative URL.
-}
toRelative : UrlPath -> String
toRelative parts =
    join parts
        |> String.join "/"


{-| Create a UrlPath from a path String.

    UrlPath.fromString "blog/post-1/"
        |> UrlPath.toAbsolute
        |> Expect.equal "/blog/post-1"

-}
fromString : String -> UrlPath
fromString path =
    path
        |> toSegments


{-| -}
toSegments : String -> List String
toSegments path =
    path |> String.split "/" |> List.filter ((/=) "")


{-| Turn a UrlPath to an absolute URL (with no trailing slash).
-}
toAbsolute : UrlPath -> String
toAbsolute path =
    "/" ++ toRelative path


normalize : String -> String
normalize pathPart =
    pathPart
        |> chopEnd "/"
        |> chopStart "/"
