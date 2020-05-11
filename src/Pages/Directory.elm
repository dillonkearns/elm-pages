module Pages.Directory exposing
    ( Directory
    , includes
    , indexPath, WithIndex, WithoutIndex
    , basePathToString, basePath
    , withIndex, withoutIndex
    )

{-| The `Directory` type can be used to get the children of a given directory,
check if a `PagePath` is within a `Directory`, or get the index page corresponding
to the directory (if it is a `Directory pathKey WithIndex`).

@docs Directory

@docs includes


## Getting a `Directory`'s corresponding index page

@docs indexPath, WithIndex, WithoutIndex


## Getting a `Directory`'s base path

@docs basePathToString, basePath


## Functions for use by generated code

@docs withIndex, withoutIndex

-}

import Pages.PagePath as PagePath exposing (PagePath)


{-| Represents a known Directory within your `content` folder
of your `elm-pages` site.
-}
type Directory key hasIndex
    = Directory key (List (PagePath key)) (List String)


{-| Used for a `Directory` that has an index path directly at that path. See
`Directory.indexPath`.
-}
type WithIndex
    = WithIndex


{-| Used for a `Directory` that does not have an index path directly at that path. See
`WithIndex` and `Directory.indexPath`.
-}
type WithoutIndex
    = WithoutIndex


{-| Check if the `Directory` contains the `PagePath`. This can be useful
for styling a link in the navbar if you are in that folder. Note that
the `view` function gets passed the `currentPage` (`Pages.application` from
your generated `Pages.elm` module).

    import Element exposing (Element)
    import Element.Font as Font
    import Pages.Directory as Directory exposing (Directory)

    navbar : PagePath Pages.PathKey -> Element msg
    navbar currentPage =
        Element.row [ Element.spacing 15 ]
            [ navbarLink currentPath pages.docs.directory "Docs"
            , navbarLink currentPath pages.blog.directory "Blog"
            ]

    navbarLink :
        PagePath Pages.PathKey
        -> Directory Pages.PathKey Directory.WithIndex
        -> String
        -> Element msg
    navbarLink currentPath linkDirectory displayName =
        let
            isHighlighted =
                currentPath |> Directory.includes linkDirectory
        in
        Element.link
            (if isHighlighted then
                [ Font.underline
                , Font.color Palette.color.primary
                ]

             else
                []
            )
            { url = linkDirectory |> Directory.indexPath |> PagePath.toString
            , label = Element.text displayName
            }

-}
includes : Directory key hasIndex -> PagePath key -> Bool
includes (Directory key allPagePaths directoryPath) pagePath =
    allPagePaths
        |> List.filter
            (\path ->
                PagePath.toString path
                    |> String.startsWith (toString directoryPath)
            )
        |> List.member pagePath


{-| Get the `PagePath` for the given Directory.

    import Pages
    import Pages.Directory as Directory exposing (Directory)

    blogDirectory : Directory Pages.PathKey Directory.WithIndex
    blogDirectory =
        Pages.pages.blog.directory

    -- blogDirectory |> Directory.indexPath |> PagePath.toString
    -- => "blog"

See `Directory.includes` for an example of this in action.

-}
indexPath : Directory key WithIndex -> PagePath key
indexPath (Directory key allPagePaths directoryPath) =
    PagePath.build key directoryPath


{-| Get the path of the directory as a String. Same as `directory |> Directory.basePath |> String.join "/"`.
-}
basePathToString : Directory key hasIndex -> String
basePathToString (Directory key allPagePaths directoryPath) =
    toString directoryPath


{-| Gives you the parts of the path of the directory.
-}
basePath : Directory key hasIndex -> List String
basePath (Directory key allPagePaths directoryPath) =
    directoryPath


toString : List String -> String
toString =
    String.join "/"


{-| Used by the generated `Pages.elm` module. There's no need to use this
outside of the generated code.
-}
withIndex : key -> List (PagePath key) -> List String -> Directory key WithIndex
withIndex key allPagePaths path =
    Directory key allPagePaths path


{-| Used by the generated `Pages.elm` module. There's no need to use this
outside of the generated code.
-}
withoutIndex : key -> List (PagePath key) -> List String -> Directory key WithoutIndex
withoutIndex key allPagePaths path =
    Directory key allPagePaths path
