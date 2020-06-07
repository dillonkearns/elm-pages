module StaticPages exposing (pages)

import Element exposing (Element)
import MarkdownRenderer
import Metadata exposing (Metadata)
import OptimizedDecoder as Decode exposing (Decoder)
import Pages.StaticHttp as StaticHttp
import Secrets


type alias View msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )


type alias CreatePagePayload =
    { path : List String
    , json : Decode.Value
    }


pages :
    List
        { entries : StaticHttp.Request (List CreatePagePayload)
        , metadata : Decoder Metadata
        , body : Decoder (View msg)
        }
pages =
    [ { entries = staticRequest
      , metadata = entryDecoder |> Decode.map Metadata.ShowcaseEntry
      , body = Decode.succeed ( [], [] )
      }
    ]


staticRequest : StaticHttp.Request (List CreatePagePayload)
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
        (Decode.field "records"
            (Decode.list
                (Decode.map2 CreatePagePayload
                    showcaseSlugDecoder
                    Decode.value
                )
            )
        )


type alias Entry =
    { screenshotUrl : String
    , displayName : String
    , liveUrl : String
    , authorName : String
    , authorUrl : String
    , categories : List String
    , repoUrl : Maybe String
    }


showcaseSlugDecoder : Decoder (List String)
showcaseSlugDecoder =
    Decode.map (\siteUrl -> [ "showcase", siteUrl ])
        (Decode.at [ "fields", "Live URL" ] Decode.string)


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
