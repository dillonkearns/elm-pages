module Showcase exposing (..)

import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import BackendTask.Http
import BuildError exposing (BuildError)
import Exception exposing (Throwable)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra


type alias Entry =
    { screenshotUrl : String
    , displayName : String
    , liveUrl : String
    , authorName : String
    , authorUrl : String
    , categories : List String
    , repoUrl : Maybe String
    }


decoder : Decoder (List Entry)
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
            (Json.Decode.Extra.optionalField "Categories" (Decode.list Decode.string) |> Decode.map (Maybe.withDefault []))
            (Decode.maybe (Decode.field "Repository URL" Decode.string))


staticRequest : BackendTask Throwable (List Entry)
staticRequest =
    Env.expect "AIRTABLE_TOKEN"
        |> BackendTask.throw
        |> BackendTask.andThen
            (\airtableToken ->
                BackendTask.Http.request
                    { url = "https://api.airtable.com/v0/appDykQzbkQJAidjt/elm-pages%20showcase?maxRecords=100&view=Grid%202"
                    , method = "GET"
                    , headers = [ ( "Authorization", "Bearer " ++ airtableToken ), ( "view", "viwayJBsr63qRd7q3" ) ]
                    , body = BackendTask.Http.emptyBody
                    , retries = Nothing
                    , timeoutInMs = Nothing
                    }
                    (BackendTask.Http.expectJson decoder)
                    |> BackendTask.throw
            )
