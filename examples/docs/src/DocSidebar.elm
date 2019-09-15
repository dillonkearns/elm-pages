module DocSidebar exposing (view)

import Element exposing (Element)
import Element.Border as Border
import Element.Font
import Metadata exposing (Metadata)
import Pages.PagePath as PagePath exposing (PagePath)
import PagesNew
import Palette


view :
    PagePath PagesNew.PathKey
    -> List ( PagePath PagesNew.PathKey, Metadata )
    -> Element msg
view currentPage posts =
    Element.column
        [ Element.spacing 10
        , Border.widthEach { bottom = 0, left = 0, right = 1, top = 0 }
        , Border.color (Element.rgba255 40 80 40 0.4)
        , Element.padding 12
        , Element.height Element.fill
        ]
        (posts
            |> List.filterMap
                (\( path, metadata ) ->
                    case metadata of
                        Metadata.Page meta ->
                            Nothing

                        Metadata.Article meta ->
                            Nothing

                        Metadata.Author _ ->
                            Nothing

                        Metadata.Doc meta ->
                            Just ( currentPage == path, path, meta )

                        Metadata.BlogIndex ->
                            Nothing
                )
            |> List.map postSummary
        )


postSummary :
    ( Bool, PagePath PagesNew.PathKey, { title : String } )
    -> Element msg
postSummary ( isCurrentPage, postPath, post ) =
    [ Element.text post.title ]
        |> Element.paragraph
            ([ Element.Font.size 18
             , Element.Font.family [ Element.Font.typeface "Roboto" ]
             , Element.Font.semiBold
             , Element.padding 16
             ]
                ++ (if isCurrentPage then
                        [ Element.Font.underline
                        , Element.Font.color Palette.color.primary
                        ]

                    else
                        []
                   )
            )
        |> linkToPost postPath


linkToPost : PagePath PagesNew.PathKey -> Element msg -> Element msg
linkToPost postPath content =
    Element.link [ Element.width Element.fill ]
        { url = PagePath.toString postPath, label = content }


docUrl : List String -> String
docUrl postPath =
    "/"
        ++ String.join "/" postPath
