module Pages.Internal.Platform.ToJsPayload exposing (..)

import BuildError
import Codec exposing (Codec)
import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode
import Pages.ImagePath as ImagePath
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath
import TerminalText as Terminal


type ToJsPayload pathKey
    = Errors String
    | Success (ToJsSuccessPayload pathKey)


type alias ToJsSuccessPayload pathKey =
    { pages : Dict String (Dict String String)
    , manifest : Manifest.Config pathKey
    , filesToGenerate : List FileToGenerate
    , staticHttpCache : Dict String String
    , errors : List String
    }


type alias ToJsSuccessPayloadNew =
    { route : String
    , html : String
    , contentJson : Dict String String
    , errors : List String
    }


type alias FileToGenerate =
    { path : List String
    , content : String
    }


toJsPayload :
    Dict String (Dict String String)
    -> Manifest.Config pathKey
    -> List FileToGenerate
    -> Dict String (Maybe String)
    -> List { title : String, message : List Terminal.Text, fatal : Bool }
    -> ToJsPayload pathKey
toJsPayload encodedStatic manifest generated allRawResponses allErrors =
    if allErrors |> List.filter .fatal |> List.isEmpty then
        Success
            (ToJsSuccessPayload
                encodedStatic
                manifest
                generated
                (allRawResponses
                    |> Dict.toList
                    |> List.filterMap
                        (\( key, maybeValue ) ->
                            maybeValue
                                |> Maybe.map (\value -> ( key, value ))
                        )
                    |> Dict.fromList
                )
                (List.map BuildError.errorToString allErrors)
            )

    else
        Errors <| BuildError.errorsToString allErrors


toJsCodec : Codec (ToJsPayload pathKey)
toJsCodec =
    Codec.custom
        (\errorsTag success value ->
            case value of
                Errors errorList ->
                    errorsTag errorList

                Success { pages, manifest, filesToGenerate, errors, staticHttpCache } ->
                    success (ToJsSuccessPayload pages manifest filesToGenerate staticHttpCache errors)
        )
        |> Codec.variant1 "Errors" Errors Codec.string
        |> Codec.variant1 "Success" Success successCodec
        |> Codec.buildCustom


stubManifest : Manifest.Config pathKey
stubManifest =
    { backgroundColor = Nothing
    , categories = []
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Nothing
    , startUrl = PagePath.external ""
    , shortName = Just "elm-pages"
    , sourceIcon = ImagePath.external ""
    }


successCodec : Codec (ToJsSuccessPayload pathKey)
successCodec =
    Codec.object ToJsSuccessPayload
        |> Codec.field "pages"
            .pages
            (Codec.dict (Codec.dict Codec.string))
        |> Codec.field "manifest"
            .manifest
            (Codec.build Manifest.toJson (Decode.succeed stubManifest))
        |> Codec.field "filesToGenerate"
            .filesToGenerate
            (Codec.build
                (\list ->
                    list
                        |> Json.Encode.list
                            (\item ->
                                Json.Encode.object
                                    [ ( "path", item.path |> String.join "/" |> Json.Encode.string )
                                    , ( "content", item.content |> Json.Encode.string )
                                    ]
                            )
                )
                (Decode.list
                    (Decode.map2 (\path content -> { path = path, content = content })
                        (Decode.string |> Decode.map (String.split "/") |> Decode.field "path")
                        (Decode.string |> Decode.field "content")
                    )
                )
            )
        |> Codec.field "staticHttpCache"
            .staticHttpCache
            (Codec.dict Codec.string)
        |> Codec.field "errors" .errors (Codec.list Codec.string)
        |> Codec.buildObject


successCodecNew : Codec ToJsSuccessPayloadNew
successCodecNew =
    Codec.object ToJsSuccessPayloadNew
        |> Codec.field "route"
            .route
            Codec.string
        |> Codec.field "html"
            .html
            Codec.string
        |> Codec.field "contentJson"
            .contentJson
            (Codec.dict Codec.string)
        |> Codec.field "errors" .errors (Codec.list Codec.string)
        |> Codec.buildObject
