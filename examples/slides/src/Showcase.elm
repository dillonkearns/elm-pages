module Showcase exposing (..)

import Element
import Element.Border
import Element.Font
import FontAwesome
import OptimizedDecoder as Decode
import Pages.Secrets as Secrets
import Pages.StaticHttp as StaticHttp
import Palette


view : List Entry -> Element.Element msg
view entries =
    Element.column
        [ Element.spacing 30
        ]
        (submitShowcaseItemButton
            :: List.map entryView entries
        )


submitShowcaseItemButton =
    Element.newTabLink
        [ Element.Font.color Palette.color.primary
        , Element.Font.underline
        ]
        { url = "https://airtable.com/shrPSenIW2EQqJ083"
        , label = Element.text "Submit your site to the showcase"
        }


entryView : Entry -> Element.Element msg
entryView entry =
    Element.column
        [ Element.spacing 15
        , Element.Border.shadow { offset = ( 2, 2 ), size = 3, blur = 3, color = Element.rgba255 40 80 80 0.1 }
        , Element.padding 40
        , Element.width (Element.maximum 700 Element.fill)
        ]
        [ Element.newTabLink [ Element.Font.size 14, Element.Font.color Palette.color.primary ]
            { url = entry.liveUrl
            , label =
                Element.image [ Element.width Element.fill ]
                    { src = "https://image.thum.io/get/width/800/crop/800/" ++ entry.screenshotUrl
                    , description = "Site Screenshot"
                    }
            }
        , Element.text entry.displayName |> Element.el [ Element.Font.extraBold ]
        , Element.newTabLink [ Element.Font.size 14, Element.Font.color Palette.color.primary ]
            { url = entry.liveUrl
            , label = Element.text entry.liveUrl
            }
        , Element.paragraph [ Element.Font.size 14 ]
            [ Element.text "By "
            , Element.newTabLink [ Element.Font.color Palette.color.primary ]
                { url = entry.authorUrl
                , label = Element.text entry.authorName
                }
            ]
        , Element.row [ Element.width Element.fill ]
            [ categoriesView entry.categories
            , Element.row [ Element.alignRight ]
                [ case entry.repoUrl of
                    Just repoUrl ->
                        Element.newTabLink []
                            { url = repoUrl
                            , label = FontAwesome.icon "fas fa-code-branch"
                            }

                    Nothing ->
                        Element.none
                ]
            ]
        ]


categoriesView : List String -> Element.Element msg
categoriesView categories =
    categories
        |> List.map
            (\category ->
                Element.text category
            )
        |> Element.wrappedRow
            [ Element.spacing 7
            , Element.Font.size 14
            , Element.Font.color (Element.rgba255 0 0 0 0.6)
            , Element.width (Element.fillPortion 8)
            ]


type alias Entry =
    { screenshotUrl : String
    , displayName : String
    , liveUrl : String
    , authorName : String
    , authorUrl : String
    , categories : List String
    , repoUrl : Maybe String
    }


decoder : Decode.Decoder (List Entry)
decoder =
    Decode.field "records" <|
        Decode.list entryDecoder


entryDecoder : Decode.Decoder Entry
entryDecoder =
    Decode.field "fields" <|
        Decode.map7 Entry
            (Decode.field "Screenshot URL" Decode.string)
            (Decode.field "Site Display Name" Decode.string)
            (Decode.field "Live URL" Decode.string)
            (Decode.field "Author" Decode.string)
            (Decode.field "Author URL" Decode.string)
            (Decode.field "Categories" (Decode.list Decode.string))
            (Decode.maybe (Decode.field "Repository URL" Decode.string))


staticRequest : StaticHttp.Request (List Entry)
staticRequest =
    StaticHttp.request
        (Secrets.succeed
            (\airtableToken ->
                { url = "https://api.airtable.com/v0/appDykQzbkQJAidjt/elm-pages%20showcase?maxRecords=100&view=Grid%202"
                , method = "GET"
                , headers = [ ( "Authorization", "Bearer " ++ airtableToken ), ( "view", "viwayJBsr63qRd7q3" ) ]
                , body = StaticHttp.emptyBody
                }
            )
            |> Secrets.with "AIRTABLE_TOKEN"
        )
        decoder


allCategroies : List String
allCategroies =
    [ "Documentation"
    , "eCommerce"
    , "Conference"
    , "Consulting"
    , "Education"
    , "Entertainment"
    , "Event"
    , "Food"
    , "Freelance"
    , "Gallery"
    , "Landing Page"
    , "Music"
    , "Nonprofit"
    , "Podcast"
    , "Portfolio"
    , "Programming"
    , "Sports"
    , "Travel"
    , "Blog"
    ]
