module Pages.Internal.Platform.Cli exposing (Flags, Model, Msg(..), Program, cliApplication, init, requestDecoder, update)

{-| Exposed for internal use only (used in generated code).

@docs Flags, Model, Msg, Program, cliApplication, init, requestDecoder, update

-}

import ApiRoute
import BuildError exposing (BuildError)
import Bytes exposing (Bytes)
import Bytes.Encode
import Codec
import DataSource exposing (DataSource)
import DataSource.Http exposing (RequestDetails)
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import HtmlPrinter
import Internal.ApiRoute exposing (ApiRoute(..))
import Json.Decode as Decode
import Json.Encode
import PageServerResponse exposing (PageServerResponse)
import Pages.Flags
import Pages.Http
import Pages.Internal.NotFoundReason as NotFoundReason exposing (NotFoundReason)
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.StaticResponses as StaticResponses exposing (StaticResponses)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload
import Pages.Internal.ResponseSketch as ResponseSketch
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.SiteConfig exposing (SiteConfig)
import Pages.StaticHttp.Request
import Pages.StaticHttpRequest as StaticHttpRequest
import Path exposing (Path)
import RenderRequest exposing (RenderRequest)
import RequestsAndPending exposing (RequestsAndPending)
import Server.Response
import Task
import TerminalText as Terminal
import Url


{-| -}
type alias Flags =
    Decode.Value


{-| -}
type alias Model route =
    { staticResponses : StaticResponses
    , errors : List BuildError
    , allRawResponses : RequestsAndPending
    , unprocessedPages : List ( Path, route )
    , maybeRequestJson : RenderRequest route
    , isDevServer : Bool
    }


{-| -}
type Msg
    = GotDataBatch
        (List
            { request : RequestDetails
            , response : RequestsAndPending.Response
            }
        )
    | GotBuildError BuildError
    | Continue


{-| -}
type alias Program route =
    Platform.Program Flags (Model route) Msg


{-| -}
cliApplication :
    ProgramConfig userMsg userModel (Maybe route) pageData sharedData
    -> Program (Maybe route)
cliApplication config =
    let
        site : SiteConfig
        site =
            getSiteConfig config

        getSiteConfig : ProgramConfig userMsg userModel (Maybe route) pageData sharedData -> SiteConfig
        getSiteConfig fullConfig =
            case fullConfig.site of
                Just mySite ->
                    mySite

                Nothing ->
                    getSiteConfig fullConfig
    in
    Platform.worker
        { init =
            \flags ->
                let
                    renderRequest : RenderRequest (Maybe route)
                    renderRequest =
                        Decode.decodeValue (RenderRequest.decoder config) flags
                            |> Result.withDefault RenderRequest.default
                in
                init site renderRequest config flags
                    |> Tuple.mapSecond (perform site renderRequest config)
        , update =
            \msg model ->
                update site config msg model
                    |> Tuple.mapSecond (perform site model.maybeRequestJson config)
        , subscriptions =
            \_ ->
                Sub.batch
                    [ config.fromJsPort
                        |> Sub.map
                            (\jsonValue ->
                                let
                                    decoder : Decode.Decoder Msg
                                    decoder =
                                        Decode.field "tag" Decode.string
                                            |> Decode.andThen
                                                (\tag ->
                                                    case tag of
                                                        "BuildError" ->
                                                            Decode.field "data"
                                                                (Decode.map2
                                                                    (\message title ->
                                                                        { title = title
                                                                        , message = message
                                                                        , fatal = True
                                                                        , path = "" -- TODO wire in current path here
                                                                        }
                                                                    )
                                                                    (Decode.field "message" Decode.string |> Decode.map Terminal.fromAnsiString)
                                                                    (Decode.field "title" Decode.string)
                                                                )
                                                                |> Decode.map GotBuildError

                                                        _ ->
                                                            Decode.fail "Unhandled msg"
                                                )
                                in
                                Decode.decodeValue decoder jsonValue
                                    |> Result.mapError Decode.errorToString
                                    |> Result.withDefault Continue
                            )
                    , config.gotBatchSub
                        |> Sub.map
                            (\newBatch ->
                                newBatch
                                    |> List.foldl
                                        (\item batchSoFar ->
                                            case batchSoFar of
                                                Err error ->
                                                    Err error

                                                Ok okBatchSoFar ->
                                                    case
                                                        Result.map2
                                                            (\request response ->
                                                                { request = request
                                                                , response = response
                                                                }
                                                            )
                                                            (item.requestAndResponse
                                                                |> Decode.decodeValue (Decode.field "request" requestDecoder)
                                                            )
                                                            (item.requestAndResponse
                                                                |> Decode.decodeValue (Decode.field "response" (RequestsAndPending.decoder item.maybeBytes))
                                                            )
                                                    of
                                                        Ok okValue ->
                                                            Ok (okValue :: okBatchSoFar)

                                                        Err error ->
                                                            Err (Decode.errorToString error |> BuildError.internal)
                                        )
                                        (Ok [])
                                    |> Result.map GotDataBatch
                                    |> Result.mapError GotBuildError
                                    |> mergeResult
                            )
                    ]
        }


mergeResult : Result a a -> a
mergeResult r =
    case r of
        Ok rr ->
            rr

        Err rr ->
            rr


{-| -}
requestDecoder : Decode.Decoder Pages.StaticHttp.Request.Request
requestDecoder =
    Pages.StaticHttp.Request.codec
        |> Codec.decoder


flatten : SiteConfig -> RenderRequest route -> ProgramConfig userMsg userModel route pageData sharedData -> List Effect -> Cmd Msg
flatten site renderRequest config list =
    Cmd.batch (flattenHelp [] site renderRequest config list)


flattenHelp : List (Cmd Msg) -> SiteConfig -> RenderRequest route -> ProgramConfig userMsg userModel route pageData sharedData -> List Effect -> List (Cmd Msg)
flattenHelp soFar site renderRequest config list =
    case list of
        first :: rest ->
            flattenHelp
                (perform site renderRequest config first :: soFar)
                site
                renderRequest
                config
                rest

        [] ->
            soFar


perform :
    SiteConfig
    -> RenderRequest route
    -> ProgramConfig userMsg userModel route pageData sharedData
    -> Effect
    -> Cmd Msg
perform site renderRequest config effect =
    let
        canonicalSiteUrl : String
        canonicalSiteUrl =
            site.canonicalUrl
    in
    case effect of
        Effect.NoEffect ->
            Cmd.none

        Effect.Batch list ->
            flatten site renderRequest config list

        Effect.FetchHttp unmasked ->
            if unmasked.url == "$$elm-pages$$headers" then
                case
                    renderRequest
                        |> RenderRequest.maybeRequestPayload
                        |> Maybe.map (\json -> RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody json))
                        |> Result.fromMaybe (Pages.Http.BadUrl "$$elm-pages$$headers is only available on server-side request (not on build).")
                of
                    Ok okResponse ->
                        Task.succeed
                            [ { request = unmasked
                              , response = okResponse
                              }
                            ]
                            |> Task.perform GotDataBatch

                    Err error ->
                        { title = "Static HTTP Error"
                        , message =
                            [ Terminal.text "I got an error making an HTTP request to this URL: "

                            -- TODO include HTTP method, headers, and body
                            , Terminal.yellow unmasked.url
                            , Terminal.text <| Json.Encode.encode 2 <| StaticHttpBody.encode unmasked.body
                            , Terminal.text "\n\n"
                            , case error of
                                Pages.Http.BadStatus metadata body ->
                                    Terminal.text <|
                                        String.join "\n"
                                            [ "Bad status: " ++ String.fromInt metadata.statusCode
                                            , "Status message: " ++ metadata.statusText
                                            , "Body: " ++ body
                                            ]

                                Pages.Http.BadUrl _ ->
                                    -- TODO include HTTP method, headers, and body
                                    Terminal.text <| "Invalid url: " ++ unmasked.url

                                Pages.Http.Timeout ->
                                    Terminal.text "Timeout"

                                Pages.Http.NetworkError ->
                                    Terminal.text "Network error"
                            ]
                        , fatal = True
                        , path = "" -- TODO wire in current path here
                        }
                            |> Task.succeed
                            |> Task.perform GotBuildError

            else
                ToJsPayload.DoHttp unmasked
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                    |> config.toJsPort
                    |> Cmd.map never

        Effect.SendSinglePage info ->
            let
                currentPagePath : String
                currentPagePath =
                    case info of
                        ToJsPayload.PageProgress toJsSuccessPayloadNew ->
                            toJsSuccessPayloadNew.route

                        _ ->
                            ""
            in
            info
                |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl currentPagePath)
                |> config.toJsPort
                |> Cmd.map never

        Effect.SendSinglePageNew rawBytes info ->
            let
                currentPagePath : String
                currentPagePath =
                    case info of
                        ToJsPayload.PageProgress toJsSuccessPayloadNew ->
                            toJsSuccessPayloadNew.route

                        _ ->
                            ""
            in
            { oldThing =
                info
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl currentPagePath)
            , binaryPageData = rawBytes
            }
                |> config.sendPageData
                |> Cmd.map never

        Effect.Continue ->
            Cmd.none


flagsDecoder :
    Decode.Decoder
        { staticHttpCache : RequestsAndPending
        , isDevServer : Bool
        }
flagsDecoder =
    Decode.map2
        (\staticHttpCache isDevServer ->
            { staticHttpCache = staticHttpCache
            , isDevServer = isDevServer
            }
        )
        --(Decode.field "staticHttpCache"
        --    (Decode.dict
        --        (Decode.string
        --            |> Decode.map Just
        --        )
        --    )
        --)
        -- TODO remove hardcoding and decode staticHttpCache here
        (Decode.succeed Dict.empty)
        (Decode.field "mode" Decode.string |> Decode.map (\mode -> mode == "dev-server"))


{-| -}
init :
    SiteConfig
    -> RenderRequest route
    -> ProgramConfig userMsg userModel route pageData sharedData
    -> Decode.Value
    -> ( Model route, Effect )
init site renderRequest config flags =
    case Decode.decodeValue flagsDecoder flags of
        Ok { staticHttpCache, isDevServer } ->
            initLegacy site renderRequest { staticHttpCache = staticHttpCache, isDevServer = isDevServer } config

        Err error ->
            updateAndSendPortIfDone
                site
                config
                { staticResponses = StaticResponses.empty
                , errors =
                    [ { title = "Internal Error"
                      , message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ]
                      , fatal = True
                      , path = ""
                      }
                    ]
                , allRawResponses = Dict.empty
                , unprocessedPages = []
                , maybeRequestJson = renderRequest
                , isDevServer = False
                }


initLegacy :
    SiteConfig
    -> RenderRequest route
    -> { staticHttpCache : RequestsAndPending, isDevServer : Bool }
    -> ProgramConfig userMsg userModel route pageData sharedData
    -> ( Model route, Effect )
initLegacy site renderRequest { staticHttpCache, isDevServer } config =
    let
        staticResponses : StaticResponses
        staticResponses =
            case renderRequest of
                RenderRequest.SinglePage _ singleRequest _ ->
                    case singleRequest of
                        RenderRequest.Page serverRequestPayload ->
                            StaticResponses.renderSingleRoute
                                (DataSource.map3 (\_ _ _ -> ())
                                    (config.data serverRequestPayload.frontmatter)
                                    config.sharedData
                                    (config.globalHeadTags |> Maybe.withDefault (DataSource.succeed []))
                                )
                                (if isDevServer then
                                    config.handleRoute serverRequestPayload.frontmatter

                                 else
                                    DataSource.succeed Nothing
                                )

                        RenderRequest.Api ( path, ApiRoute apiRequest ) ->
                            StaticResponses.renderApiRequest
                                (DataSource.map2 (\_ _ -> ())
                                    (apiRequest.matchesToResponse path)
                                    (config.globalHeadTags |> Maybe.withDefault (DataSource.succeed []))
                                )

                        RenderRequest.NotFound _ ->
                            StaticResponses.renderApiRequest
                                (DataSource.map2 (\_ _ -> ())
                                    (DataSource.succeed [])
                                    (config.globalHeadTags |> Maybe.withDefault (DataSource.succeed []))
                                )

        unprocessedPages : List ( Path, route )
        unprocessedPages =
            case renderRequest of
                RenderRequest.SinglePage _ serverRequestPayload _ ->
                    case serverRequestPayload of
                        RenderRequest.Page pageData ->
                            [ ( pageData.path, pageData.frontmatter ) ]

                        RenderRequest.Api _ ->
                            []

                        RenderRequest.NotFound _ ->
                            []

        initialModel : Model route
        initialModel =
            { staticResponses = staticResponses
            , errors = []
            , allRawResponses = staticHttpCache
            , unprocessedPages = unprocessedPages
            , maybeRequestJson = renderRequest
            , isDevServer = isDevServer
            }
    in
    StaticResponses.nextStep initialModel Nothing
        |> nextStepToEffect site
            config
            initialModel


updateAndSendPortIfDone :
    SiteConfig
    -> ProgramConfig userMsg userModel route pageData sharedData
    -> Model route
    -> ( Model route, Effect )
updateAndSendPortIfDone site config model =
    StaticResponses.nextStep
        model
        Nothing
        |> nextStepToEffect site config model


{-| -}
update :
    SiteConfig
    -> ProgramConfig userMsg userModel route pageData sharedData
    -> Msg
    -> Model route
    -> ( Model route, Effect )
update site config msg model =
    case msg of
        GotDataBatch batch ->
            let
                updatedModel : Model route
                updatedModel =
                    model
                        |> StaticResponses.batchUpdate batch
            in
            StaticResponses.nextStep
                updatedModel
                Nothing
                |> nextStepToEffect site config updatedModel

        Continue ->
            let
                updatedModel : Model route
                updatedModel =
                    model
            in
            StaticResponses.nextStep
                updatedModel
                Nothing
                |> nextStepToEffect site config updatedModel

        GotBuildError buildError ->
            let
                updatedModel : Model route
                updatedModel =
                    { model
                        | errors =
                            buildError :: model.errors
                    }
            in
            StaticResponses.nextStep
                updatedModel
                Nothing
                |> nextStepToEffect site config updatedModel


nextStepToEffect :
    SiteConfig
    -> ProgramConfig userMsg userModel route pageData sharedData
    -> Model route
    -> ( StaticResponses, StaticResponses.NextStep route )
    -> ( Model route, Effect )
nextStepToEffect site config model ( updatedStaticResponsesModel, nextStep ) =
    case nextStep of
        StaticResponses.Continue updatedAllRawResponses httpRequests maybeRoutes ->
            let
                updatedUnprocessedPages : List ( Path, route )
                updatedUnprocessedPages =
                    case maybeRoutes of
                        Just newRoutes ->
                            newRoutes
                                |> List.map
                                    (\route ->
                                        ( Path.join (config.routeToPath route)
                                        , route
                                        )
                                    )

                        Nothing ->
                            model.unprocessedPages

                updatedModel : Model route
                updatedModel =
                    { model
                        | allRawResponses = updatedAllRawResponses
                        , staticResponses = updatedStaticResponsesModel
                        , unprocessedPages = updatedUnprocessedPages
                    }
            in
            if List.isEmpty httpRequests then
                nextStepToEffect site
                    config
                    updatedModel
                    (StaticResponses.nextStep
                        updatedModel
                        Nothing
                    )

            else
                ( updatedModel
                , (httpRequests
                    |> List.map Effect.FetchHttp
                  )
                    |> Effect.Batch
                )

        StaticResponses.Finish toJsPayload ->
            case toJsPayload of
                StaticResponses.ApiResponse ->
                    let
                        apiResponse : Effect
                        apiResponse =
                            case model.maybeRequestJson of
                                RenderRequest.SinglePage _ requestPayload _ ->
                                    case requestPayload of
                                        RenderRequest.Api ( path, ApiRoute apiHandler ) ->
                                            let
                                                thing : DataSource (Maybe ApiRoute.Response)
                                                thing =
                                                    apiHandler.matchesToResponse path
                                            in
                                            StaticHttpRequest.resolve
                                                thing
                                                model.allRawResponses
                                                |> Result.mapError (StaticHttpRequest.toBuildError "TODO - path from request")
                                                |> (\response ->
                                                        case response of
                                                            Ok (Just okResponse) ->
                                                                { body = okResponse
                                                                , staticHttpCache = Dict.empty -- TODO do I need to serialize the full cache here, or can I handle that from the JS side?

                                                                -- model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                , statusCode = 200
                                                                }
                                                                    |> ToJsPayload.SendApiResponse
                                                                    |> Effect.SendSinglePage

                                                            Ok Nothing ->
                                                                render404Page config model (Path.fromString path) NotFoundReason.NoMatchingRoute

                                                            Err error ->
                                                                [ error ]
                                                                    |> ToJsPayload.Errors
                                                                    |> Effect.SendSinglePage
                                                   )

                                        RenderRequest.Page payload ->
                                            let
                                                pageFoundResult : Result BuildError (Maybe NotFoundReason)
                                                pageFoundResult =
                                                    StaticHttpRequest.resolve
                                                        (if model.isDevServer then
                                                            -- TODO OPTIMIZATION this is redundant
                                                            config.handleRoute payload.frontmatter

                                                         else
                                                            DataSource.succeed Nothing
                                                        )
                                                        model.allRawResponses
                                                        |> Result.mapError (StaticHttpRequest.toBuildError (payload.path |> Path.toAbsolute))
                                            in
                                            case pageFoundResult of
                                                Ok Nothing ->
                                                    sendSinglePageProgress site model.allRawResponses config model payload

                                                Ok (Just notFoundReason) ->
                                                    render404Page config model payload.path notFoundReason

                                                Err error ->
                                                    [ error ] |> ToJsPayload.Errors |> Effect.SendSinglePage

                                        RenderRequest.NotFound path ->
                                            render404Page config
                                                model
                                                path
                                                (NotFoundReason.NotPrerendered
                                                    { moduleName = []
                                                    , routePattern =
                                                        { segments = []
                                                        , ending = Nothing
                                                        }
                                                    , matchedRouteParams = []
                                                    }
                                                    []
                                                )
                    in
                    ( model
                    , apiResponse
                    )

                StaticResponses.Errors errors ->
                    ( model
                    , errors |> ToJsPayload.Errors |> Effect.SendSinglePage
                    )


sendSinglePageProgress :
    SiteConfig
    -> RequestsAndPending
    -> ProgramConfig userMsg userModel route pageData sharedData
    -> Model route
    -> { path : Path, frontmatter : route }
    -> Effect
sendSinglePageProgress site contentJson config model info =
    let
        ( page, route ) =
            ( info.path, info.frontmatter )
    in
    case model.maybeRequestJson of
        RenderRequest.SinglePage includeHtml _ _ ->
            let
                pageFoundResult : Result BuildError (Maybe NotFoundReason)
                pageFoundResult =
                    -- TODO OPTIMIZATION this is redundant
                    StaticHttpRequest.resolve
                        (if model.isDevServer then
                            config.handleRoute route

                         else
                            DataSource.succeed Nothing
                        )
                        model.allRawResponses
                        |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                renderedResult : Result BuildError (PageServerResponse { head : List Head.Tag, view : String, title : String })
                renderedResult =
                    case includeHtml of
                        RenderRequest.OnlyJson ->
                            Ok
                                (Server.Response.render
                                    { head = []
                                    , view = "This page was not rendered because it is a JSON-only request."
                                    , title = "This page was not rendered because it is a JSON-only request."
                                    }
                                )

                        RenderRequest.HtmlAndJson ->
                            Result.map2 Tuple.pair pageDataResult sharedDataResult
                                |> Result.map
                                    (\( pageData_, sharedData ) ->
                                        case pageData_ of
                                            PageServerResponse.RenderPage responseInfo pageData ->
                                                let
                                                    currentPage : { path : Path, route : route }
                                                    currentPage =
                                                        { path = page, route = config.urlToRoute currentUrl }

                                                    pageModel : userModel
                                                    pageModel =
                                                        config.init
                                                            Pages.Flags.PreRenderFlags
                                                            sharedData
                                                            pageData
                                                            Nothing
                                                            (Just
                                                                { path =
                                                                    { path = currentPage.path
                                                                    , query = Nothing
                                                                    , fragment = Nothing
                                                                    }
                                                                , metadata = currentPage.route
                                                                , pageUrl = Nothing
                                                                }
                                                            )
                                                            |> Tuple.first

                                                    viewValue : { title : String, body : Html userMsg }
                                                    viewValue =
                                                        (config.view currentPage Nothing sharedData pageData |> .view) pageModel
                                                in
                                                PageServerResponse.RenderPage responseInfo
                                                    { head = config.view currentPage Nothing sharedData pageData |> .head
                                                    , view = viewValue.body |> HtmlPrinter.htmlToString
                                                    , title = viewValue.title
                                                    }

                                            PageServerResponse.ServerResponse serverResponse ->
                                                PageServerResponse.ServerResponse serverResponse
                                    )

                currentUrl : Url.Url
                currentUrl =
                    { protocol = Url.Https
                    , host = site.canonicalUrl
                    , port_ = Nothing
                    , path = page |> Path.toRelative
                    , query = Nothing
                    , fragment = Nothing
                    }

                pageDataResult : Result BuildError (PageServerResponse pageData)
                pageDataResult =
                    -- TODO OPTIMIZATION can these three be included in StaticResponses.Finish?
                    StaticHttpRequest.resolve
                        (config.data (config.urlToRoute currentUrl))
                        contentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                sharedDataResult : Result BuildError sharedData
                sharedDataResult =
                    StaticHttpRequest.resolve
                        config.sharedData
                        contentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                siteDataResult : Result BuildError (List Head.Tag)
                siteDataResult =
                    StaticHttpRequest.resolve
                        (config.globalHeadTags |> Maybe.withDefault (DataSource.succeed []))
                        model.allRawResponses
                        |> Result.mapError (StaticHttpRequest.toBuildError "Site.elm")
            in
            case Result.map3 (\a b c -> ( a, b, c )) pageFoundResult renderedResult siteDataResult of
                Ok ( maybeNotFoundReason, renderedOrApiResponse, siteData ) ->
                    case maybeNotFoundReason of
                        Nothing ->
                            case renderedOrApiResponse of
                                PageServerResponse.RenderPage responseInfo rendered ->
                                    let
                                        byteEncodedPageData : Bytes
                                        byteEncodedPageData =
                                            case pageDataResult of
                                                Ok pageServerResponse ->
                                                    case pageServerResponse of
                                                        PageServerResponse.RenderPage _ pageData ->
                                                            -- TODO want to encode both shared and page data in dev server and HTML-embedded data
                                                            -- but not for writing out the content.dat files - would be good to optimize this redundant data out
                                                            --if model.isDevServer then
                                                            if True then
                                                                sharedDataResult
                                                                    |> Result.map (ResponseSketch.HotUpdate pageData)
                                                                    |> Result.withDefault (ResponseSketch.RenderPage pageData)
                                                                    |> config.encodeResponse
                                                                    |> Bytes.Encode.encode

                                                            else
                                                                pageData
                                                                    |> ResponseSketch.RenderPage
                                                                    |> config.encodeResponse
                                                                    |> Bytes.Encode.encode

                                                        PageServerResponse.ServerResponse serverResponse ->
                                                            -- TODO handle error?
                                                            PageServerResponse.toRedirect serverResponse
                                                                |> Maybe.map
                                                                    (\{ location } ->
                                                                        location
                                                                            |> ResponseSketch.Redirect
                                                                            |> config.encodeResponse
                                                                    )
                                                                -- TODO handle other cases besides redirects?
                                                                |> Maybe.withDefault (Bytes.Encode.unsignedInt8 0)
                                                                |> Bytes.Encode.encode

                                                _ ->
                                                    -- TODO handle error?
                                                    Bytes.Encode.encode (Bytes.Encode.unsignedInt8 0)
                                    in
                                    { route = page |> Path.toRelative
                                    , contentJson = Dict.empty
                                    , html = rendered.view
                                    , errors = []
                                    , head = rendered.head ++ siteData
                                    , title = rendered.title
                                    , staticHttpCache = Dict.empty

                                    -- TODO can I handle caching from the JS-side only?
                                    --model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                    , is404 = False
                                    , statusCode = responseInfo.statusCode
                                    , headers = responseInfo.headers
                                    }
                                        |> ToJsPayload.PageProgress
                                        |> Effect.SendSinglePageNew byteEncodedPageData

                                PageServerResponse.ServerResponse serverResponse ->
                                    { body = serverResponse |> PageServerResponse.toJson
                                    , staticHttpCache = Dict.empty

                                    -- TODO can I handle caching from the JS-side only?
                                    --model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                    , statusCode = 200
                                    }
                                        |> ToJsPayload.SendApiResponse
                                        |> Effect.SendSinglePage

                        Just notFoundReason ->
                            render404Page config model page notFoundReason

                Err error ->
                    [ error ]
                        |> ToJsPayload.Errors
                        |> Effect.SendSinglePage


render404Page :
    ProgramConfig userMsg userModel route pageData sharedData
    -> Model route
    -> Path
    -> NotFoundReason
    -> Effect
render404Page config model path notFoundReason =
    let
        notFoundDocument : { title : String, body : Html msg }
        notFoundDocument =
            { path = path
            , reason = notFoundReason
            }
                |> NotFoundReason.document config.pathPatterns

        byteEncodedPageData : Bytes
        byteEncodedPageData =
            { reason = notFoundReason, path = path }
                |> ResponseSketch.NotFound
                |> config.encodeResponse
                |> Bytes.Encode.encode
    in
    { route = Path.toAbsolute path
    , contentJson = Dict.empty
    , html = HtmlPrinter.htmlToString notFoundDocument.body
    , errors = []
    , head = []
    , title = notFoundDocument.title
    , staticHttpCache = Dict.empty

    -- TODO can I handle caching from the JS-side only?
    --model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
    , is404 = True
    , statusCode = 404
    , headers = []
    }
        |> ToJsPayload.PageProgress
        |> Effect.SendSinglePageNew byteEncodedPageData
