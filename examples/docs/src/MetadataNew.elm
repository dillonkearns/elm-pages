module MetadataNew exposing (DocMetadata, PageMetadata, decoder)

import Json.Decode as Decode exposing (Decoder)
import Template.BlogPost
import Template.Page
import Template.Showcase
import TemplateType exposing (TemplateType)


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }


decoder : Decoder TemplateType
decoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\pageType ->
                case pageType of
                    "doc" ->
                        Decode.field "title" Decode.string
                            |> Decode.map (\title -> TemplateType.Documentation { title = title })

                    "page" ->
                        Template.Page.decoder
                            |> Decode.map TemplateType.Page

                    "blog-index" ->
                        Decode.succeed {}
                            |> Decode.map TemplateType.BlogIndex

                    "showcase" ->
                        Template.Showcase.decoder
                            |> Decode.map TemplateType.Showcase

                    "blog" ->
                        Template.BlogPost.decoder
                            |> Decode.map TemplateType.BlogPost

                    _ ->
                        Decode.fail <| "Unexpected page \"type\" " ++ pageType
            )
