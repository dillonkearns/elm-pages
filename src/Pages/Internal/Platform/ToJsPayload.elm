module Pages.Internal.Platform.ToJsPayload exposing (..)

import BuildError
import Codec exposing (Codec)
import Dict exposing (Dict)
import Head
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


type alias ToJsSuccessPayloadNew pathKey =
    { route : String
    , html : String
    , contentJson : Dict String String
    , errors : List String
    , head : List (Head.Tag pathKey)
    , body : String
    , title : String
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


toJsCodec : String -> Codec (ToJsPayload pathKey)
toJsCodec canonicalSiteUrl =
    Codec.custom
        (\errorsTag success value ->
            case value of
                Errors errorList ->
                    errorsTag errorList

                Success { pages, manifest, filesToGenerate, errors, staticHttpCache } ->
                    success (ToJsSuccessPayload pages manifest filesToGenerate staticHttpCache errors)
        )
        |> Codec.variant1 "Errors" Errors Codec.string
        |> Codec.variant1 "Success" Success (successCodec canonicalSiteUrl)
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
    , icons = []
    }


successCodec : String -> Codec (ToJsSuccessPayload pathKey)
successCodec canonicalSiteUrl =
    Codec.object ToJsSuccessPayload
        |> Codec.field "pages"
            .pages
            (Codec.dict (Codec.dict Codec.string))
        |> Codec.field "manifest"
            .manifest
            (Codec.build (Manifest.toJson canonicalSiteUrl) (Decode.succeed stubManifest))
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


successCodecNew : String -> String -> Codec (ToJsSuccessPayloadNew pathKey)
successCodecNew canonicalSiteUrl currentPagePath =
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
        |> Codec.field "head" .head (Codec.list (headCodec canonicalSiteUrl currentPagePath))
        |> Codec.field "body" .body Codec.string
        |> Codec.field "title" .title Codec.string
        |> Codec.buildObject


headCodec : String -> String -> Codec (Head.Tag pathKey)
headCodec canonicalSiteUrl currentPagePath =
    Codec.build (Head.toJson canonicalSiteUrl currentPagePath)
        (Decode.succeed (Head.canonicalLink Nothing))


type ToJsSuccessPayloadNewCombined pathKey
    = PageProgress (ToJsSuccessPayloadNew pathKey)
    | InitialData (InitialDataRecord pathKey)


type alias InitialDataRecord pathKey =
    { filesToGenerate : List FileToGenerate
    , manifest : Manifest.Config pathKey
    }


successCodecNew2 : String -> String -> Codec (ToJsSuccessPayloadNewCombined pathKey)
successCodecNew2 canonicalSiteUrl currentPagePath =
    Codec.custom
        (\success initialData value ->
            case value of
                PageProgress payload ->
                    success payload

                InitialData payload ->
                    initialData payload
        )
        |> Codec.variant1 "PageProgress" PageProgress (successCodecNew canonicalSiteUrl currentPagePath)
        |> Codec.variant1 "InitialData" InitialData (initialDataCodec canonicalSiteUrl)
        |> Codec.buildCustom


manifestCodec : String -> Codec (Manifest.Config pathKey)
manifestCodec canonicalSiteUrl =
    Codec.build (Manifest.toJson canonicalSiteUrl) (Decode.succeed stubManifest)


filesToGenerateCodec : Codec (List { path : List String, content : String })
filesToGenerateCodec =
    Codec.build
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


initialDataCodec : String -> Codec (InitialDataRecord pathKey)
initialDataCodec canonicalSiteUrl =
    Codec.object InitialDataRecord
        |> Codec.field "filesToGenerate"
            .filesToGenerate
            filesToGenerateCodec
        |> Codec.field "manifest"
            .manifest
            (manifestCodec canonicalSiteUrl)
        |> Codec.buildObject
