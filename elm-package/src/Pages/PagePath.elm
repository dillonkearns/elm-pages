module Pages.PagePath exposing (PagePath, build, external, inFolder, toString)

{-| You can get data representing type-safe, guaranteed-available
routes from your generated `Pages` module in your repo. If the file
is not available, make sure you've run `elm-pages develop`.

The `key` in the `PagePath key` type protects you from using
a route that is not from the static routes that the generated
`Pages.elm` module provides. That means that if you use one of these values,
you can completely trust it and get helpful compiler errors if you mispell something
or access a dead link!

The static `PagePath`s for your site are generated so you can grab them in
two ways:


## List-based `PagePath` lookup

You will find a list of all the pages in your app in this generated code:

    Pages.allPages : List (PagePath Pages.PathKey)

This is handy for creating an index page, for example showing all
the blog posts in your site.


## Record-based `PagePath` lookup

You can lookup a specific static route based on its path using the record-based lookup:

    Pages.allPages : List (PagePath Pages.PathKey)

This is useful for referring to static routes directly from your Elm code (you'll
need a different technique for verifying that a link in your markup content
is valid).

For example, you might have a navbar that links to specific routes.


## Using

You can use this information to

-}


{-| There are only two ways to get a `PagePath` representing a static route
in your site.

1.  Get a value using the generated `Pages.elm` module in your repo, or
2.  Generate an external route using `PagePath.external`.

-}
type PagePath key
    = Internal (List String)
    | External String


inFolder : PagePath key -> PagePath key -> Bool
inFolder folder page =
    toString page
        |> String.startsWith (toString folder)


toString : PagePath key -> String
toString path =
    case path of
        Internal rawPath ->
            "/"
                ++ (rawPath |> String.join "/")

        External url ->
            url


external : String -> PagePath key
external url =
    External url


build : key -> List String -> PagePath key
build key path =
    Internal path
