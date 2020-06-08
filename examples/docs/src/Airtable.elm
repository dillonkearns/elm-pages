module Airtable exposing (pages)

import OptimizedDecoder as Decode exposing (Decoder)
import Pages.StaticHttp as StaticHttp
import Secrets


type alias CreatePagePayload =
    { path : List String
    , json : Decode.Value
    }


pages :
    Config
    ->
        { metadata : Decoder metadata
        , body : Decoder body
        }
    ->
        { entries : StaticHttp.Request (List CreatePagePayload)
        , metadata : Decoder metadata
        , body : Decoder body
        }
pages config decoders =
    { entries = staticRequest config
    , metadata = decoders.metadata
    , body = decoders.body
    }


type alias Config =
    { viewId : String
    , maxRecords : Int
    , airtableAccountId : String
    , viewName : String
    , entryToRoute : Decoder (List String)
    }


staticRequest :
    { viewId : String
    , maxRecords : Int
    , airtableAccountId : String
    , viewName : String
    , entryToRoute : Decoder (List String)
    }
    -> StaticHttp.Request (List CreatePagePayload)
staticRequest config =
    StaticHttp.request
        (Secrets.succeed
            (\airtableToken ->
                { url =
                    "https://api.airtable.com/v0/"
                        ++ config.airtableAccountId
                        ++ "/elm-pages%20showcase?maxRecords="
                        ++ String.fromInt config.maxRecords
                        ++ "&view="
                        ++ config.viewName
                , method = "GET"
                , headers = [ ( "Authorization", "Bearer " ++ airtableToken ), ( "view", config.viewId ) ]
                , body = StaticHttp.emptyBody
                }
            )
            |> Secrets.with "AIRTABLE_TOKEN"
        )
        (Decode.field "records"
            (Decode.list
                (Decode.map2 CreatePagePayload
                    config.entryToRoute
                    Decode.value
                )
            )
        )
