module DocSidebar exposing (view)

import Element exposing (Element)
import Element.Border as Border
import Element.Font
import Metadata exposing (Metadata)
import Pages
import Pages.PagePath as PagePath exposing (PagePath)
import Palette
import TemplateType


view :
    PagePath Pages.PathKey
    -> List ( PagePath Pages.PathKey, TemplateType.Metadata )
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
                        TemplateType.Documentation meta ->
                            Just ( currentPage == path, path, meta )

                        _ ->
                            Nothing
                )
            |> List.map postSummary
        )


postSummary :
    ( Bool, PagePath Pages.PathKey, { title : String } )
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


linkToPost : PagePath Pages.PathKey -> Element msg -> Element msg
linkToPost postPath content =
    Element.link [ Element.width Element.fill ]
        { url = PagePath.toString postPath, label = content }


docUrl : List String -> String
docUrl postPath =
    "/"
        ++ String.join "/" postPath
