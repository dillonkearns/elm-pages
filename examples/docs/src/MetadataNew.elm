module MetadataNew exposing (DocMetadata, PageMetadata, decoder)

import Cloudinary
import Data.Author
import Date exposing (Date)
import Json.Decode as Decode exposing (Decoder)
import Pages
import Pages.ImagePath exposing (ImagePath)
import Template.BlogPost
import Template.Page
import Template.Showcase
import TemplateType exposing (TemplateType)


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , author : Data.Author.Author
    , image : ImagePath Pages.PathKey
    , draft : Bool
    }


decoder : Decoder TemplateType
decoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\pageType ->
                case pageType of
                    "doc" ->
                        Decode.field "title" Decode.string
                            |> Decode.map (\title -> TemplateType.Documentation { title = title })

                    "blog-index" ->
                        Decode.succeed {}
                            |> Decode.map TemplateType.BlogIndex

                    "blog" ->
                        Decode.map6 ArticleMetadata
                            (Decode.field "title" Decode.string)
                            (Decode.field "description" Decode.string)
                            (Decode.field "published"
                                (Decode.string
                                    |> Decode.andThen
                                        (\isoString ->
                                            case Date.fromIsoString isoString of
                                                Ok date ->
                                                    Decode.succeed date

                                                Err error ->
                                                    Decode.fail error
                                        )
                                )
                            )
                            (Decode.field "author" Data.Author.decoder)
                            (Decode.field "image" imageDecoder)
                            (Decode.field "draft" Decode.bool
                                |> Decode.maybe
                                |> Decode.map (Maybe.withDefault False)
                            )
                            |> Decode.map TemplateType.BlogPost

                    _ ->
                        Decode.fail <| "Unexpected page \"type\" " ++ pageType
            )


imageDecoder : Decoder (ImagePath Pages.PathKey)
imageDecoder =
    Decode.string
        |> Decode.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)
