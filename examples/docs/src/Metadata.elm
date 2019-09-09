module Metadata exposing (ArticleMetadata, DocMetadata, Metadata(..), PageMetadata, decoder)

import Date exposing (Date)
import Dict exposing (Dict)
import Element exposing (Element)
import Element.Font as Font
import Json.Decode as Decode
import Pages.Path as Path exposing (Path)
import PagesNew


type Metadata
    = Page PageMetadata
    | Article ArticleMetadata
    | Doc DocMetadata


type alias ArticleMetadata =
    { author : String
    , title : String
    , description : String
    , published : Date
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

                    "blog" ->
                        Decode.map4 ArticleMetadata
                            (Decode.field "author" Decode.string)
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
                            |> Decode.map Article

                    _ ->
                        Decode.fail <| "Unexpected page type " ++ pageType
            )
