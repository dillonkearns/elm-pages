module Pages.Internal.Platform.ToJsPayload exposing
    ( FileToGenerate
    , InitialDataRecord
    , ToJsPayload(..)
    , ToJsSuccessPayload
    , ToJsSuccessPayloadNew
    , ToJsSuccessPayloadNewCombined(..)
    , successCodecNew2
    , toJsCodec
    , toJsPayload
    )

import BuildError exposing (BuildError)
import Codec exposing (Codec)
import Dict exposing (Dict)
import Head
import Json.Decode as Decode
import Json.Encode
import Pages.StaticHttp.Request


type ToJsPayload
    = Errors (List BuildError)
    | Success ToJsSuccessPayload
    | ApiResponse


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
    , title : String
    , staticHttpCache : Dict String String
    , is404 : Bool
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
        (\errorsTag success vApiResponse value ->
            case value of
                Errors errorList ->
                    errorsTag errorList

                Success { pages, filesToGenerate, errors, staticHttpCache } ->
                    success (ToJsSuccessPayload pages filesToGenerate staticHttpCache errors)

                ApiResponse ->
                    vApiResponse
        )
        |> Codec.variant1 "Errors" Errors errorCodec
        |> Codec.variant1 "Success" Success successCodec
        |> Codec.variant0 "ApiResponse" ApiResponse
        |> Codec.buildCustom


errorCodec : Codec (List BuildError)
errorCodec =
    Codec.object (\errorString _ -> errorString)
        |> Codec.field "errorString"
            identity
            (Codec.build (BuildError.errorsToString >> Json.Encode.string)
                (Decode.string
                    |> Decode.map (\value -> [ { title = value, path = "Intentionally empty", message = [], fatal = False } ])
                )
            )
        |> Codec.field "errorsJson"
            identity
            (Codec.build
                (Json.Encode.list BuildError.encode)
                (Decode.succeed [ { title = "TODO", message = [], fatal = True, path = "" } ])
            )
        |> Codec.buildObject


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
        |> Codec.field "title" .title Codec.string
        |> Codec.field "staticHttpCache"
            .staticHttpCache
            (Codec.dict Codec.string)
        |> Codec.field "is404" .is404 Codec.bool
        |> Codec.buildObject


headCodec : String -> String -> Codec Head.Tag
headCodec canonicalSiteUrl currentPagePath =
    Codec.build (Head.toJson canonicalSiteUrl currentPagePath)
        (Decode.succeed (Head.canonicalLink Nothing))


type ToJsSuccessPayloadNewCombined
    = PageProgress ToJsSuccessPayloadNew
    | InitialData InitialDataRecord
    | SendApiResponse { body : String, staticHttpCache : Dict String String, statusCode : Int }
    | ReadFile String
    | Glob String
    | DoHttp { masked : Pages.StaticHttp.Request.Request, unmasked : Pages.StaticHttp.Request.Request }
    | Port String


type alias InitialDataRecord =
    { filesToGenerate : List FileToGenerate
    }


successCodecNew2 : String -> String -> Codec ToJsSuccessPayloadNewCombined
successCodecNew2 canonicalSiteUrl currentPagePath =
    Codec.custom
        (\success initialData vReadFile vGlob vDoHttp vSendApiResponse vPort value ->
            case value of
                PageProgress payload ->
                    success payload

                InitialData payload ->
                    initialData payload

                ReadFile filePath ->
                    vReadFile filePath

                Glob globPattern ->
                    vGlob globPattern

                DoHttp requestUrl ->
                    vDoHttp requestUrl

                SendApiResponse record ->
                    vSendApiResponse record

                Port string ->
                    vPort string
        )
        |> Codec.variant1 "PageProgress" PageProgress (successCodecNew canonicalSiteUrl currentPagePath)
        |> Codec.variant1 "InitialData" InitialData initialDataCodec
        |> Codec.variant1 "ReadFile" ReadFile Codec.string
        |> Codec.variant1 "Glob" Glob Codec.string
        |> Codec.variant1 "DoHttp"
            DoHttp
            (Codec.object (\masked unmasked -> { masked = masked, unmasked = unmasked })
                |> Codec.field "masked" .masked Pages.StaticHttp.Request.codec
                |> Codec.field "unmasked" .unmasked Pages.StaticHttp.Request.codec
                |> Codec.buildObject
            )
        |> Codec.variant1 "ApiResponse"
            SendApiResponse
            (Codec.object (\body staticHttpCache statusCode -> { body = body, staticHttpCache = staticHttpCache, statusCode = statusCode })
                |> Codec.field "body" .body Codec.string
                |> Codec.field "staticHttpCache"
                    .staticHttpCache
                    (Codec.dict Codec.string)
                |> Codec.field "statusCode" .statusCode Codec.int
                |> Codec.buildObject
            )
        |> Codec.variant1 "Port" Port Codec.string
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
