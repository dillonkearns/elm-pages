module Pages.Internal.Platform.ToJsPayload exposing (..)

import BuildError exposing (BuildError)
import Codec exposing (Codec)
import Dict exposing (Dict)
import Head
import Json.Decode as Decode
import Json.Encode
import Pages.ImagePath as ImagePath
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath


type ToJsPayload
    = Errors (List BuildError)
    | Success ToJsSuccessPayload


type alias ToJsSuccessPayload =
    { pages : Dict String (Dict String String)
    , filesToGenerate : List FileToGenerate
    , staticHttpCache : Dict String String
    , errors : List BuildError
    }


type alias ToJsSuccessPayloadNew =
    { route : String
    , html : String
    , contentJson : Dict String String
    , errors : List String
    , head : List Head.Tag
    , body : String
    , title : String
    , staticHttpCache : Dict String String
    }


type alias FileToGenerate =
    { path : List String
    , content : String
    }


toJsPayload :
    Dict String (Dict String String)
    -> List FileToGenerate
    -> Dict String (Maybe String)
    -> List BuildError
    -> ToJsPayload
toJsPayload encodedStatic generated allRawResponses allErrors =
    if allErrors |> List.filter .fatal |> List.isEmpty then
        Success
            (ToJsSuccessPayload
                encodedStatic
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
                allErrors
            )

    else
        Errors <| allErrors


toJsCodec : Codec ToJsPayload
toJsCodec =
    Codec.custom
        (\errorsTag success value ->
            case value of
                Errors errorList ->
                    errorsTag errorList

                Success { pages, filesToGenerate, errors, staticHttpCache } ->
                    success (ToJsSuccessPayload pages filesToGenerate staticHttpCache errors)
        )
        |> Codec.variant1 "Errors" Errors errorCodec
        |> Codec.variant1 "Success" Success successCodec
        |> Codec.buildCustom


errorCodec : Codec (List BuildError)
errorCodec =
    Codec.object (\_ _ -> [])
        |> Codec.field "errorString"
            identity
            (Codec.string
                |> Codec.map
                    (\_ ->
                        [ { title = "TODO"
                          , message = []
                          , fatal = True
                          , path = ""
                          }
                        ]
                    )
                    BuildError.errorsToString
            )
        |> Codec.field "errorsJson"
            identity
            (Codec.build
                (Json.Encode.list BuildError.encode)
                (Decode.succeed [ { title = "TODO", message = [], fatal = True, path = "" } ])
            )
        |> Codec.buildObject


stubManifest : Manifest.Config
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


successCodec : Codec ToJsSuccessPayload
successCodec =
    Codec.object ToJsSuccessPayload
        |> Codec.field "pages"
            .pages
            (Codec.dict (Codec.dict Codec.string))
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
        |> Codec.field "errors" .errors errorCodec
        |> Codec.buildObject


successCodecNew : String -> String -> Codec ToJsSuccessPayloadNew
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
        |> Codec.field "staticHttpCache"
            .staticHttpCache
            (Codec.dict Codec.string)
        |> Codec.buildObject


headCodec : String -> String -> Codec Head.Tag
headCodec canonicalSiteUrl currentPagePath =
    Codec.build (Head.toJson canonicalSiteUrl currentPagePath)
        (Decode.succeed (Head.canonicalLink Nothing))


type ToJsSuccessPayloadNewCombined
    = PageProgress ToJsSuccessPayloadNew
    | InitialData InitialDataRecord
    | ReadFile String
    | Glob String


type alias InitialDataRecord =
    { filesToGenerate : List FileToGenerate
    }


successCodecNew2 : String -> String -> Codec ToJsSuccessPayloadNewCombined
successCodecNew2 canonicalSiteUrl currentPagePath =
    Codec.custom
        (\success initialData vReadFile vGlob value ->
            case value of
                PageProgress payload ->
                    success payload

                InitialData payload ->
                    initialData payload

                ReadFile filePath ->
                    vReadFile filePath

                Glob globPattern ->
                    vGlob globPattern
        )
        |> Codec.variant1 "PageProgress" PageProgress (successCodecNew canonicalSiteUrl currentPagePath)
        |> Codec.variant1 "InitialData" InitialData initialDataCodec
        |> Codec.variant1 "ReadFile" ReadFile Codec.string
        |> Codec.variant1 "Glob" Glob Codec.string
        |> Codec.buildCustom


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


initialDataCodec : Codec InitialDataRecord
initialDataCodec =
    Codec.object InitialDataRecord
        |> Codec.field "filesToGenerate"
            .filesToGenerate
            filesToGenerateCodec
        |> Codec.buildObject
