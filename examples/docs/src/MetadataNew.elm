module MetadataNew exposing (DocMetadata, PageMetadata, decoder)

import GlobalMetadata as Metadata exposing (Metadata)
import Json.Decode as Decode exposing (Decoder)
import Template.BlogPost
import Template.Page
import Template.Showcase


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }


decoder : Decoder Metadata
decoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\pageType ->
                case pageType of
                    "doc" ->
                        Decode.field "title" Decode.string
                            |> Decode.map (\title -> Metadata.MetadataDocumentation { title = title })

                    "page" ->
                        Template.Page.decoder
                            |> Decode.map Metadata.MetadataPage

                    "blog-index" ->
                        Decode.succeed {}
                            |> Decode.map Metadata.MetadataBlogIndex

                    "showcase" ->
                        Template.Showcase.decoder
                            |> Decode.map Metadata.MetadataShowcase

                    "blog" ->
                        Template.BlogPost.decoder
                            |> Decode.map Metadata.MetadataBlogPost

                    _ ->
                        Decode.fail <| "Unexpected page \"type\" " ++ pageType
            )
