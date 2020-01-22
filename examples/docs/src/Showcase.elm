module Showcase exposing (..)

import Element
import Json.Decode.Exploration as Decode
import Pages.Secrets as Secrets
import Pages.StaticHttp as StaticHttp


view : List Entry -> Element.Element msg
view entries =
    Element.column
        [ Element.spacing 30
        ]
        (List.map entryView entries)


entryView : Entry -> Element.Element msg
entryView entry =
    Element.column [ Element.spacing 10 ]
        [ Element.text entry.displayName
        , Element.newTabLink []
            { url = entry.liveUrl
            , label = Element.text entry.liveUrl
            }
        , Element.paragraph []
            [ Element.text "By "
            , Element.newTabLink []
                { url = entry.authorUrl
                , label = Element.text entry.authorName
                }
            ]
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
