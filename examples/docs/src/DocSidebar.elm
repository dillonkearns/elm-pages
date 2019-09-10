module DocSidebar exposing (view)

import Element exposing (Element)
import Element.Border as Border
import Element.Font
import Metadata exposing (Metadata)


view :
    List ( List String, Metadata )
    -> Element msg
view posts =
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
                            Just ( path, meta )

                        Metadata.BlogIndex ->
                            Nothing
                )
            |> List.map postSummary
        )


postSummary :
    ( List String, { title : String } )
    -> Element msg
postSummary ( postPath, post ) =
    [ Element.text post.title ]
        |> Element.paragraph
            [ Element.Font.size 18
            , Element.Font.family [ Element.Font.typeface "Roboto" ]
            , Element.Font.semiBold
            , Element.padding 16
            ]
        |> linkToPost postPath


linkToPost : List String -> Element msg -> Element msg
linkToPost postPath content =
    Element.link [ Element.width Element.fill ]
        { url = docUrl postPath, label = content }


docUrl : List String -> String
docUrl postPath =
    "/"
        ++ String.join "/" postPath
