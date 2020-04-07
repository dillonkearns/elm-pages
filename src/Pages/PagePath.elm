module Pages.PagePath exposing
    ( PagePath, toString, external
    , build
    , toPath
    )

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

    Pages.pages

This gives you a record, based on your local `content` directory, that lets you look paths up like so:

    import Pages
    import Pages.PagePath as PagePath exposing (PagePath)

    homePath : PagePath Pages.PathKey
    homePath =
        Pages.pages.index

    -- PagePath.toString homePath
    -- => ""

or

    import Pages
    import Pages.PagePath as PagePath exposing (PagePath)

    helloWorldPostPath : PagePath Pages.PathKey
    helloWorldPostPath =
        Pages.pages.blog.helloWorld

    -- PagePath.toString helloWorldPostPath
    -- => "blog/hello-world"

Note that in the `hello-world` example it changes from the kebab casing of the actual
URL to camelCasing for the record key.

This is useful for referring to static routes directly from your Elm code (you'll
need a different technique for verifying that a link in your markup content
is valid).

For example, you might have a navbar that links to specific routes.

@docs PagePath, toString, external, toPath


## Functions for code generation only

Don't bother using these.

@docs build

-}


{-| There are only two ways to get a `PagePath`:

1.  Get a value using the generated `Pages.elm` module in your repo (see above), or
2.  Generate an external route using `PagePath.external`.

So `PagePath` represents either a 1) known, static page path, or 2) an
external page path (which is not validated so use these carefully!).

-}
type PagePath key
    = Internal (List String)
    | External String


{-| Gives you the page's relative URL as a String. This is useful for constructing links:

    import Html exposing (Html, a)
    import Html.Attributes exposing (href)
    import Pages
    import Pages.PagePath as PagePath exposing (PagePath)


    -- `Pages` is a generated module
    homePath : PagePath Pages.PathKey
    homePath =
        Pages.pages.index

    linkToHome : Html msg
    linkToHome =
        a [ href (PagePath.toString homePath) ] [ text "🏡 Home" ]

-}
toString : PagePath key -> String
toString path =
    case path of
        Internal rawPath ->
            String.join "/" rawPath

        External url ->
            url


{-| Get a List of each part of the path.

    indexPathParts =
        PagePath.toPath Pages.pages.index == []

    blogPostPathParts =
        PagePath.toPath Pages.pages.blog.hello == [ "blog", "hello" ]

-}
toPath : PagePath key -> List String
toPath path =
    case path of
        Internal rawPath ->
            rawPath

        External url ->
            []


{-| This allows you to build a URL to an external resource. Avoid using
`PagePath.external` to refer to statically available routes. Instead, use
this only to point to outside pages.

    import Pages
    import Pages.PagePath as PagePath exposing (PagePath)


    -- The `Pages` module is generated in your codebase.
    -- Notice that we can still annotate this external link
    -- with `Pages.PathKey`, since external links are always valid
    -- (unlike internal routes, which are guaranteed to be present
    -- if your code compiles).
    googlePath : PagePath Pages.PathKey
    googlePath =
        PagePath.external "https://google.com"

-}
external : String -> PagePath key
external url =
    External url


{-| This is not useful except for the internal generated code to construct a PagePath.
-}
build : key -> List String -> PagePath key
build key path =
    Internal path
