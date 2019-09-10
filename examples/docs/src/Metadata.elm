module Metadata exposing (ArticleMetadata, DocMetadata, Metadata(..), PageMetadata, decoder)

import Date exposing (Date)
import Dict exposing (Dict)
import Element exposing (Element)
import Element.Font as Font
import Json.Decode as Decode exposing (Decoder)
import List.Extra
import Pages.Path as Path exposing (Path)
import PagesNew


type Metadata
    = Page PageMetadata
    | Article ArticleMetadata
    | Doc DocMetadata
    | Author AuthorMetadata


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , author : AuthorMetadata
    }


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }


decoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\pageType ->
                case pageType of
                    "doc" ->
                        Decode.field "title" Decode.string
                            |> Decode.map (\title -> Doc { title = title })

                    "page" ->
                        Decode.field "title" Decode.string
                            |> Decode.map (\title -> Page { title = title })

                    "author" ->
                        Decode.map3 AuthorMetadata
                            (Decode.field "name" Decode.string)
                            (Decode.field "avatar" imageDecoder)
                            (Decode.field "bio" Decode.string)
                            |> Decode.map Author

                    "blog" ->
                        Decode.map4 ArticleMetadata
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
                            (Decode.field "author" authorDecoder)
                            |> Decode.map Article

                    _ ->
                        Decode.fail <| "Unexpected page type " ++ pageType
            )


type alias AuthorMetadata =
    { name : String
    , avatar : Path PagesNew.PathKey Path.ToImage
    , bio : String
    }


authorDecoder : Decoder AuthorMetadata
authorDecoder =
    Decode.string
        |> Decode.andThen
            (\authorName ->
                Decode.succeed
                    { name = "Dillon Kearns"
                    , avatar = PagesNew.images.dillon
                    , bio = ""
                    }
            )


imageDecoder : Decoder (Path PagesNew.PathKey Path.ToImage)
imageDecoder =
    Decode.string
        |> Decode.andThen
            (\imageAssetPath ->
                case findMatchingImage imageAssetPath of
                    Nothing ->
                        Decode.fail "Couldn't find image."

                    Just imagePath ->
                        Decode.succeed imagePath
            )


findMatchingImage : String -> Maybe (Path PagesNew.PathKey Path.ToImage)
findMatchingImage imageAssetPath =
    PagesNew.allImages
        |> List.Extra.find
            (\image ->
                Path.toString image
                    == imageAssetPath
            )
