module Index exposing (view)

--import Pages.Metadata as Metadata exposing (Metadata)

import Data.Author
import Date
import Element exposing (Element)
import Element.Border
import Element.Font
import GlobalMetadata
import Pages
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Template.Metadata exposing (BlogPost)


view :
    List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    -> Element msg
view posts =
    Element.column [ Element.spacing 20 ]
        (posts
            |> List.filterMap
                (\( path, metadata ) ->
                    case metadata of
                        GlobalMetadata.MetadataBlogPost meta ->
                            if meta.draft then
                                Nothing

                            else
                                Just ( path, meta )

                        _ ->
                            Nothing
                )
            |> List.sortBy
                (\( path, metadata ) ->
                    -(metadata.published |> Date.toRataDie)
                )
            |> List.map postSummary
        )


postSummary :
    ( PagePath Pages.PathKey, BlogPost )
    -> Element msg
postSummary ( postPath, post ) =
    articleIndex post |> linkToPost postPath


linkToPost : PagePath Pages.PathKey -> Element msg -> Element msg
linkToPost postPath content =
    Element.link [ Element.width Element.fill ]
        { url = PagePath.toString postPath, label = content }


title : String -> Element msg
title text =
    [ Element.text text ]
        |> Element.paragraph
            [ Element.Font.size 36
            , Element.Font.center
            , Element.Font.family [ Element.Font.typeface "Montserrat" ]
            , Element.Font.semiBold
            , Element.padding 16
            ]


articleIndex : BlogPost -> Element msg
articleIndex metadata =
    Element.el
        [ Element.centerX
        , Element.width (Element.maximum 600 Element.fill)
        , Element.padding 40
        , Element.spacing 10
        , Element.Border.width 1
        , Element.Border.color (Element.rgba255 0 0 0 0.1)
        , Element.mouseOver
            [ Element.Border.color (Element.rgba255 0 0 0 1)
            ]
        ]
        (postPreview metadata)


grey =
    Element.Font.color (Element.rgba255 0 0 0 0.5)


postPreview : BlogPost -> Element msg
postPreview post =
    Element.textColumn
        [ Element.centerX
        , Element.width Element.fill
        , Element.spacing 30
        , Element.Font.size 18
        ]
        [ title post.title
        , Element.image [ Element.width Element.fill ] { src = post.image |> ImagePath.toString, description = "Blog post cover photo" }
        , Element.row
            [ Element.spacing 10
            , Element.centerX
            , grey
            ]
            [ Data.Author.view [ Element.width (Element.px 40) ] post.author
            , Element.text post.author.name
            , Element.text "•"
            , Element.text (post.published |> Date.format "MMMM ddd, yyyy")
            ]
        , post.description
            |> Element.text
            |> List.singleton
            |> Element.paragraph
                [ Element.Font.size 22
                , Element.Font.center
                ]
        ]
