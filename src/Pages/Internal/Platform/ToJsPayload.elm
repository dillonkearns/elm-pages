module Pages.Internal.Platform.ToJsPayload exposing
    ( NewThingForPort
    , ToJsSuccessPayloadNew
    , ToJsSuccessPayloadNewCombined(..)
    , sendToJs
    , successCodecNew2
    )

import BuildError exposing (BuildError)
import Bytes exposing (Bytes)
import Codec exposing (Codec)
import Codec.Advanced
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
    , headers : Dict String (List String)
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
            (Codec.dict (Codec.list Codec.string))
        |> Codec.buildObject


headCodec : String -> String -> Codec Head.Tag
headCodec canonicalSiteUrl currentPagePath =
    Codec.build (Head.toJson canonicalSiteUrl currentPagePath)
        (Decode.succeed (Head.canonicalLink Nothing))


type ToJsSuccessPayloadNewCombined
    = PageProgress ToJsSuccessPayloadNew
    | SendApiResponse { body : Json.Encode.Value, staticHttpCache : Dict String String, statusCode : Int }
    | DoHttp (List ( String, Pages.StaticHttp.Request.Request ))
    | Port String
    | Errors (List BuildError)
    | ApiResponse
    | PrintAndExitSuccess String
    | FetchFrozenViews { path : String, query : Maybe String, body : Maybe String }


successCodecNew2 : String -> String -> Codec ToJsSuccessPayloadNewCombined
successCodecNew2 canonicalSiteUrl currentPagePath =
    let
        variant :
            String
            -> (a -> v)
            -> Codec a
            -> Codec.Advanced.AdvancedCodec ((a -> Codec.Value) -> b) v
            -> Codec.Advanced.AdvancedCodec b v
        variant name ctor argsCodec =
            Codec.Advanced.variant ctor
                (Codec.object identity
                    |> Codec.constantField "tag" name Codec.string
                    |> Codec.field "args" identity argsCodec
                    |> Codec.buildObject
                )

        variant0 :
            String
            -> a
            -> Codec.Advanced.AdvancedCodec ((() -> Codec.Value) -> b) a
            -> Codec.Advanced.AdvancedCodec b a
        variant0 name ctor =
            variant name
                (\_ -> ctor)
                (Codec.list (Codec.fail "Expected an empty list")
                    |> Codec.andThen
                        (\l ->
                            case l of
                                [] ->
                                    Codec.succeed ()

                                h :: _ ->
                                    never h
                        )
                        (\_ -> [])
                )

        variant1 :
            String
            -> (a -> v)
            -> Codec a
            -> Codec.Advanced.AdvancedCodec ((a -> Codec.Value) -> b) v
            -> Codec.Advanced.AdvancedCodec b v
        variant1 name ctor argCodec =
            variant name
                ctor
                (Codec.list argCodec
                    |> Codec.andThen
                        (\l ->
                            case l of
                                [ x ] ->
                                    Codec.succeed x

                                _ ->
                                    Codec.fail "Expected one element"
                        )
                        List.singleton
                )
    in
    Codec.Advanced.custom
        (\errorsTag vApiResponse success vDoHttp vSendApiResponse vPort vPrintExitAndSuccess vFetchFrozenViews value ->
            case value of
                ApiResponse ->
                    vApiResponse ()

                Errors errorList ->
                    errorsTag errorList

                PageProgress payload ->
                    success payload

                DoHttp hashRequestPairs ->
                    vDoHttp hashRequestPairs

                SendApiResponse record ->
                    vSendApiResponse record

                Port string ->
                    vPort string

                PrintAndExitSuccess message ->
                    vPrintExitAndSuccess message

                FetchFrozenViews data ->
                    vFetchFrozenViews data
        )
        |> variant1 "Errors" Errors errorCodec
        |> variant0 "ApiResponse" ApiResponse
        |> variant1 "PageProgress" PageProgress (successCodecNew canonicalSiteUrl currentPagePath)
        |> variant1 "DoHttp" DoHttp (Codec.list (Codec.tuple Codec.string Pages.StaticHttp.Request.codec))
        |> variant1 "ApiResponse"
            SendApiResponse
            (Codec.object (\body staticHttpCache statusCode -> { body = body, staticHttpCache = staticHttpCache, statusCode = statusCode })
                |> Codec.field "body" .body Codec.value
                |> Codec.field "staticHttpCache"
                    .staticHttpCache
                    (Codec.dict Codec.string)
                |> Codec.field "statusCode" .statusCode Codec.int
                |> Codec.buildObject
            )
        |> variant1 "Port" Port Codec.string
        |> Codec.Advanced.variant PrintAndExitSuccess Codec.string
        |> Codec.Advanced.variant FetchFrozenViews
            (Codec.object (\path query body -> { path = path, query = query, body = body })
                |> Codec.constantField "tag" "FetchFrozenViews" Codec.string
                |> Codec.field "path" .path Codec.string
                |> Codec.field "query" .query (Codec.nullable Codec.string)
                |> Codec.field "body" .body (Codec.nullable Codec.string)
                |> Codec.buildObject
            )
        |> Codec.Advanced.build


sendToJs :
    { canonicalSiteUrl : String
    , currentPagePath : String
    , config : { config | toJsPort : Codec.Value -> Cmd Never }
    }
    -> ToJsSuccessPayloadNewCombined
    -> Cmd msg
sendToJs { canonicalSiteUrl, currentPagePath, config } payload =
    payload
        |> Codec.encoder (successCodecNew2 canonicalSiteUrl currentPagePath)
        |> config.toJsPort
        |> Cmd.map never
