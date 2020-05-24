module MetadataNew exposing (DocMetadata, PageMetadata, decoder)

import Json.Decode as Decode exposing (Decoder)
import Template.BlogPost
import Template.Showcase
import TemplateDemultiplexer as TD exposing (Metadata)


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
                    --"doc" ->
                    --    Decode.field "title" Decode.string
                    --        |> Decode.map (\title -> Doc { title = title })
                    --
                    --"page" ->
                    --    Decode.field "title" Decode.string
                    --        |> Decode.map (\title -> Page { title = title })
                    --
                    --"blog-index" ->
                    --    Decode.succeed BlogIndex
                    "showcase" ->
                        Template.Showcase.decoder
                            |> Decode.map TD.MetadataShowcase

                    --
                    --"author" ->
                    --    Decode.map3 Data.Author.Author
                    --        (Decode.field "name" Decode.string)
                    --        (Decode.field "avatar" imageDecoder)
                    --        (Decode.field "bio" Decode.string)
                    --        |> Decode.map Author
                    "blog" ->
                        Template.BlogPost.decoder
                            |> Decode.map TD.MetadataBlogPost

                    _ ->
                        Decode.fail <| "Unexpected page \"type\" " ++ pageType
            )
