module Showcase exposing (..)

import Element
import Element.Border
import Element.Font
import FontAwesome
import Json.Decode.Exploration as Decode
import Pages.Secrets as Secrets
import Pages.StaticHttp as StaticHttp
import Palette
import Url.Builder


view : List Entry -> Element.Element msg
view entries =
    Element.column
        [ Element.spacing 30
        ]
        (List.map entryView entries)


entryView : Entry -> Element.Element msg
entryView entry =
    Element.column
        [ Element.spacing 15
        , Element.Border.shadow { offset = ( 2, 2 ), size = 3, blur = 3, color = Element.rgba255 40 80 80 0.1 }
        , Element.padding 40
        , Element.width (Element.maximum 700 Element.fill)
        ]
        [ Element.image [ Element.width Element.fill ]
            { src =
                Url.Builder.crossOrigin "https://api.microlink.io"
                    []
                    [ Url.Builder.string "embed" "screenshot.url"
                    , Url.Builder.string "meta" "false"
                    , Url.Builder.string "url" entry.liveUrl
                    , Url.Builder.string "screenshot" "true"
                    ]
            , description = "Site Screenshot"
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
                [ Element.newTabLink []
                    { url = entry.authorUrl
                    , label = FontAwesome.icon "fas fa-code-branch"
                    }
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
    { displayName : String
    , liveUrl : String
    , authorName : String
    , authorUrl : String
    , categories : List String
    }


decoder : Decode.Decoder (List Entry)
decoder =
    Decode.field "records" <|
        Decode.list entryDecoder


entryDecoder : Decode.Decoder Entry
entryDecoder =
    Decode.field "fields" <|
        Decode.map5 Entry
            (Decode.field "Site Display Name" Decode.string)
            (Decode.field "Live URL" Decode.string)
            (Decode.field "Author" Decode.string)
            (Decode.field "Author URL" Decode.string)
            (Decode.field "Categories" (Decode.list Decode.string))


staticRequest : StaticHttp.Request (List Entry)
staticRequest =
    StaticHttp.request
        (Secrets.succeed
            (\airtableToken ->
                { url = "https://api.airtable.com/v0/appDykQzbkQJAidjt/elm-pages%20showcase?maxRecords=3&view=Grid%202"
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
