module StaticPages exposing (pages)

import Airtable
import Element exposing (Element)
import MarkdownRenderer
import Metadata exposing (Metadata)
import OptimizedDecoder as Decode exposing (Decoder)
import Pages.StaticHttp as StaticHttp


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
    [ Airtable.pages
        { entryToRoute = showcaseSlugDecoder
        , viewId = "viwayJBsr63qRd7q3"
        , maxRecords = 100
        , airtableAccountId = "appDykQzbkQJAidjt"
        , viewName = "Grid%202"
        }
        { metadata = entryDecoder |> Decode.map Metadata.ShowcaseEntry
        , body = Decode.succeed ( [], [] )
        }
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
