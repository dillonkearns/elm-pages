module Pages.Internal.Platform.ToJsPayload exposing
    ( NewThingForPort
    , ToJsSuccessPayloadNew
    , ToJsSuccessPayloadNewCombined(..)
    , successCodecNew2
    )

import BuildError exposing (BuildError)
import Bytes exposing (Bytes)
import Codec exposing (Codec)
import Dict exposing (Dict)
import Head
import Json.Decode as Decode
import Json.Encode
import Pages.StaticHttp.Request


type alias ToJsSuccessPayloadNew =
    { route : String
    , html : String
    , contentJson : Dict String String
    , errors : List String
    , head : List Head.Tag
    , title : String
    , staticHttpCache : Dict String String
    , is404 : Bool
    , statusCode : Int
    , headers : List ( String, String )
    }


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
                BuildError.encode
                (Decode.succeed [ { title = "TODO", message = [], fatal = True, path = "" } ])
            )
        |> Codec.buildObject


type alias NewThingForPort =
    { oldThing : Json.Encode.Value
    , binaryPageData : Bytes
    }


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
        |> Codec.field "statusCode" .statusCode Codec.int
        |> Codec.field "headers"
            .headers
            (Codec.dict Codec.string |> Codec.map Dict.toList Dict.fromList)
        |> Codec.buildObject


headCodec : String -> String -> Codec Head.Tag
headCodec canonicalSiteUrl currentPagePath =
    Codec.build (Head.toJson canonicalSiteUrl currentPagePath)
        (Decode.succeed (Head.canonicalLink Nothing))


type ToJsSuccessPayloadNewCombined
    = PageProgress ToJsSuccessPayloadNew
    | SendApiResponse { body : Json.Encode.Value, staticHttpCache : Dict String String, statusCode : Int }
    | DoHttp String Pages.StaticHttp.Request.Request
    | Port String
    | Errors (List BuildError)
    | ApiResponse


successCodecNew2 : String -> String -> Codec ToJsSuccessPayloadNewCombined
successCodecNew2 canonicalSiteUrl currentPagePath =
    Codec.custom
        (\errorsTag vApiResponse success vDoHttp vSendApiResponse vPort value ->
            case value of
                ApiResponse ->
                    vApiResponse

                Errors errorList ->
                    errorsTag errorList

                PageProgress payload ->
                    success payload

                DoHttp hash requestUrl ->
                    vDoHttp hash requestUrl

                SendApiResponse record ->
                    vSendApiResponse record

                Port string ->
                    vPort string
        )
        |> Codec.variant1 "Errors" Errors errorCodec
        |> Codec.variant0 "ApiResponse" ApiResponse
        |> Codec.variant1 "PageProgress" PageProgress (successCodecNew canonicalSiteUrl currentPagePath)
        |> Codec.variant2 "DoHttp"
            DoHttp
            Codec.string
            Pages.StaticHttp.Request.codec
        |> Codec.variant1 "ApiResponse"
            SendApiResponse
            (Codec.object (\body staticHttpCache statusCode -> { body = body, staticHttpCache = staticHttpCache, statusCode = statusCode })
                |> Codec.field "body" .body Codec.value
                |> Codec.field "staticHttpCache"
                    .staticHttpCache
                    (Codec.dict Codec.string)
                |> Codec.field "statusCode" .statusCode Codec.int
                |> Codec.buildObject
            )
        |> Codec.variant1 "Port" Port Codec.string
        |> Codec.buildCustom
