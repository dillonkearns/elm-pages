module MetadataNew exposing (DocMetadata, PageMetadata, decoder)

import Json.Decode as Decode exposing (Decoder)
import Template.BlogPost
import Template.Page
import Template.Showcase
import TemplateType as Metadata exposing (Metadata)


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
                            |> Decode.map (\title -> Metadata.Documentation { title = title })

                    "page" ->
                        Template.Page.decoder
                            |> Decode.map Metadata.Page

                    "blog-index" ->
                        Decode.succeed {}
                            |> Decode.map Metadata.BlogIndex

                    "showcase" ->
                        Template.Showcase.decoder
                            |> Decode.map Metadata.Showcase

                    "blog" ->
                        Template.BlogPost.decoder
                            |> Decode.map Metadata.BlogPost

                    _ ->
                        Decode.fail <| "Unexpected page \"type\" " ++ pageType
            )
