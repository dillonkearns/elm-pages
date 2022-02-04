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
import Dict.Extra
import Head
import Html exposing (Html)
import HtmlPrinter
import Internal.ApiRoute exposing (ApiRoute(..))
import Json.Decode as Decode
import Json.Encode
import PageServerResponse exposing (PageServerResponse)
import Pages.Flags
import Pages.Http
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
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
    , allRawResponses : Dict String (Maybe String)
    , pendingRequests : List RequestDetails
    , unprocessedPages : List ( Path, route )
    , staticRoutes : Maybe (List ( Path, route ))
    , maybeRequestJson : RenderRequest route
    , isDevServer : Bool
    }


{-| -}
type Msg
    = GotDataBatch
        (List
            { request : RequestDetails
            , response : String
            }
        )
    | GotBuildError BuildError
    | Continue


{-| -}
type alias Program route =
    Platform.Program Flags (Model route) Msg


{-| -}
cliApplication :
    ProgramConfig userMsg userModel (Maybe route) siteData pageData sharedData
    -> Program (Maybe route)
cliApplication config =
    let
        site : SiteConfig siteData
        site =
            getSiteConfig config

        getSiteConfig : ProgramConfig userMsg userModel (Maybe route) siteData pageData sharedData -> SiteConfig siteData
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
                    |> Tuple.mapSecond (perform site renderRequest config config.toJsPort)
        , update =
            \msg model ->
                update site config msg model
                    |> Tuple.mapSecond (perform site model.maybeRequestJson config config.toJsPort)
        , subscriptions =
            \_ ->
                config.fromJsPort
                    |> Sub.map
                        (\jsonValue ->
                            let
                                decoder : Decode.Decoder Msg
                                decoder =
                                    Decode.field "tag" Decode.string
                                        |> Decode.andThen
                                            (\tag ->
                                                -- tag: "GotGlob"
                                                -- tag: "GotFile"
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

                                                    "GotBatch" ->
                                                        Decode.field "data"
                                                            (Decode.list
                                                                (Decode.map2
                                                                    (\requests response ->
                                                                        { request = requests
                                                                        , response = response
                                                                        }
                                                                    )
                                                                    (Decode.field "request" requestDecoder)
                                                                    (Decode.field "response" Decode.string)
                                                                )
                                                            )
                                                            |> Decode.map GotDataBatch

                                                    _ ->
                                                        Decode.fail "Unhandled msg"
                                            )
                            in
                            Decode.decodeValue decoder jsonValue
                                |> Result.mapError Decode.errorToString
                                |> Result.withDefault Continue
                        )
        }


{-| -}
requestDecoder : Decode.Decoder Pages.StaticHttp.Request.Request
requestDecoder =
    Pages.StaticHttp.Request.codec
        |> Codec.decoder


perform :
    SiteConfig siteData
    -> RenderRequest route
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> (Codec.Value -> Cmd Never)
    -> Effect
    -> Cmd Msg
perform site renderRequest config toJsPort effect =
    -- elm-review: known-unoptimized-recursion
    let
        canonicalSiteUrl : String
        canonicalSiteUrl =
            site.canonicalUrl
    in
    case effect of
        Effect.NoEffect ->
            Cmd.none

        Effect.Batch list ->
            list
                |> List.map (perform site renderRequest config toJsPort)
                |> Cmd.batch

        Effect.FetchHttp unmasked ->
            if unmasked.url == "$$elm-pages$$headers" then
                case
                    renderRequest
                        |> RenderRequest.maybeRequestPayload
                        |> Maybe.map (Json.Encode.encode 0)
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

            else if unmasked.url |> String.startsWith "file://" then
                let
                    filePath : String
                    filePath =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.ReadFile filePath
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                    |> toJsPort
                    |> Cmd.map never

            else if unmasked.url |> String.startsWith "glob://" then
                let
                    globPattern : String
                    globPattern =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.Glob globPattern
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                    |> toJsPort
                    |> Cmd.map never

            else
                ToJsPayload.DoHttp unmasked
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                    |> toJsPort
                    |> Cmd.map never

        Effect.SendSinglePage done info ->
            let
                currentPagePath : String
                currentPagePath =
                    case info of
                        ToJsPayload.PageProgress toJsSuccessPayloadNew ->
                            toJsSuccessPayloadNew.route

                        _ ->
                            ""
            in
            Cmd.batch
                [ info
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl currentPagePath)
                    |> toJsPort
                    |> Cmd.map never
                , if done then
                    Cmd.none

                  else
                    Task.succeed ()
                        |> Task.perform (\_ -> Continue)
                ]

        Effect.SendSinglePageNew done rawBytes info ->
            let
                currentPagePath : String
                currentPagePath =
                    case info of
                        ToJsPayload.PageProgress toJsSuccessPayloadNew ->
                            toJsSuccessPayloadNew.route

                        _ ->
                            ""

                newCommandThing : Cmd a
                newCommandThing =
                    { oldThing =
                        info
                            |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl currentPagePath)
                    , binaryPageData = rawBytes
                    }
                        |> config.sendPageData
                        |> Cmd.map never
            in
            Cmd.batch
                [ newCommandThing
                , if done then
                    Cmd.none

                  else
                    Task.succeed ()
                        |> Task.perform (\_ -> Continue)
                ]

        Effect.Continue ->
            Cmd.none

        Effect.ReadFile filePath ->
            ToJsPayload.ReadFile filePath
                |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                |> toJsPort
                |> Cmd.map never

        Effect.GetGlob globPattern ->
            ToJsPayload.Glob globPattern
                |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                |> toJsPort
                |> Cmd.map never


flagsDecoder :
    Decode.Decoder
        { staticHttpCache : Dict String (Maybe String)
        , isDevServer : Bool
        }
flagsDecoder =
    Decode.map2
        (\staticHttpCache isDevServer ->
            { staticHttpCache = staticHttpCache
            , isDevServer = isDevServer
            }
        )
        (Decode.field "staticHttpCache"
            (Decode.dict
                (Decode.string
                    |> Decode.map Just
                )
            )
        )
        (Decode.field "mode" Decode.string |> Decode.map (\mode -> mode == "dev-server"))


{-| -}
init :
    SiteConfig siteData
    -> RenderRequest route
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Decode.Value
    -> ( Model route, Effect )
init site renderRequest config flags =
    case Decode.decodeValue flagsDecoder flags of
        Ok { staticHttpCache, isDevServer } ->
            initLegacy site renderRequest { staticHttpCache = staticHttpCache, isDevServer = isDevServer } config flags

        Err error ->
            updateAndSendPortIfDone
                site
                config
                { staticResponses = StaticResponses.error
                , errors =
                    [ { title = "Internal Error"
                      , message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ]
                      , fatal = True
                      , path = ""
                      }
                    ]
                , allRawResponses = Dict.empty
                , pendingRequests = []
                , unprocessedPages = []
                , staticRoutes = Just []
                , maybeRequestJson = renderRequest
                , isDevServer = False
                }


initLegacy :
    SiteConfig siteData
    -> RenderRequest route
    -> { staticHttpCache : Dict String (Maybe String), isDevServer : Bool }
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Decode.Value
    -> ( Model route, Effect )
initLegacy site renderRequest { staticHttpCache, isDevServer } config flags =
    let
        staticResponses : StaticResponses
        staticResponses =
            case renderRequest of
                RenderRequest.SinglePage _ singleRequest _ ->
                    case singleRequest of
                        RenderRequest.Page serverRequestPayload ->
                            StaticResponses.renderSingleRoute config
                                serverRequestPayload
                                (DataSource.map2 (\_ _ -> ())
                                    (config.data serverRequestPayload.frontmatter)
                                    config.sharedData
                                )
                                (if isDevServer then
                                    config.handleRoute serverRequestPayload.frontmatter

                                 else
                                    DataSource.succeed Nothing
                                )

                        RenderRequest.Api ( path, ApiRoute apiRequest ) ->
                            StaticResponses.renderApiRequest
                                (apiRequest.matchesToResponse path)

                        RenderRequest.NotFound _ ->
                            StaticResponses.renderApiRequest
                                (DataSource.succeed [])

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

        unprocessedPagesState : Maybe (List ( Path, route ))
        unprocessedPagesState =
            case renderRequest of
                RenderRequest.SinglePage _ serverRequestPayload _ ->
                    case serverRequestPayload of
                        RenderRequest.Page pageData ->
                            Just [ ( pageData.path, pageData.frontmatter ) ]

                        RenderRequest.Api _ ->
                            Nothing

                        RenderRequest.NotFound _ ->
                            Just []

        initialModel : Model route
        initialModel =
            { staticResponses = staticResponses
            , errors = []
            , allRawResponses = staticHttpCache
            , pendingRequests = []
            , unprocessedPages = unprocessedPages
            , staticRoutes = unprocessedPagesState
            , maybeRequestJson = renderRequest
            , isDevServer = isDevServer
            }
    in
    StaticResponses.nextStep config initialModel Nothing
        |> nextStepToEffect site
            config
            initialModel


updateAndSendPortIfDone :
    SiteConfig siteData
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model route
    -> ( Model route, Effect )
updateAndSendPortIfDone site config model =
    StaticResponses.nextStep
        config
        model
        Nothing
        |> nextStepToEffect site config model


{-| -}
update :
    SiteConfig siteData
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Msg
    -> Model route
    -> ( Model route, Effect )
update site config msg model =
    case msg of
        GotDataBatch batch ->
            let
                updatedModel : Model route
                updatedModel =
                    (case batch of
                        [ single ] ->
                            { model
                                | pendingRequests =
                                    model.pendingRequests
                                        |> List.filter
                                            (\pending ->
                                                pending /= single.request
                                            )
                            }

                        _ ->
                            { model
                                | pendingRequests = [] -- TODO is it safe to clear it entirely?
                            }
                    )
                        |> StaticResponses.batchUpdate batch
            in
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect site config updatedModel

        Continue ->
            let
                updatedModel : Model route
                updatedModel =
                    model
            in
            StaticResponses.nextStep config
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
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect site config updatedModel


nextStepToEffect :
    SiteConfig siteData
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model route
    -> ( StaticResponses, StaticResponses.NextStep route )
    -> ( Model route, Effect )
nextStepToEffect site config model ( updatedStaticResponsesModel, nextStep ) =
    case nextStep of
        StaticResponses.Continue updatedAllRawResponses httpRequests maybeRoutes ->
            let
                nextAndPending : List RequestDetails
                nextAndPending =
                    model.pendingRequests ++ httpRequests

                doNow : List RequestDetails
                doNow =
                    nextAndPending

                pending : List RequestDetails
                pending =
                    []

                updatedRoutes : Maybe (List ( Path, route ))
                updatedRoutes =
                    case maybeRoutes of
                        Just newRoutes ->
                            newRoutes
                                |> List.map
                                    (\route ->
                                        ( Path.join (config.routeToPath route)
                                        , route
                                        )
                                    )
                                |> Just

                        Nothing ->
                            model.staticRoutes

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
                        , pendingRequests = pending
                        , staticResponses = updatedStaticResponsesModel
                        , staticRoutes = updatedRoutes
                        , unprocessedPages = updatedUnprocessedPages
                    }
            in
            if List.isEmpty doNow && updatedRoutes /= model.staticRoutes then
                nextStepToEffect site
                    config
                    updatedModel
                    (StaticResponses.nextStep config
                        updatedModel
                        Nothing
                    )

            else
                ( updatedModel
                , (doNow
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
                                RenderRequest.SinglePage includeHtml requestPayload _ ->
                                    case requestPayload of
                                        RenderRequest.Api ( path, ApiRoute apiHandler ) ->
                                            let
                                                thing : DataSource (Maybe ApiRoute.Response)
                                                thing =
                                                    apiHandler.matchesToResponse path
                                            in
                                            StaticHttpRequest.resolve ApplicationType.Cli
                                                thing
                                                model.allRawResponses
                                                |> Result.mapError (StaticHttpRequest.toBuildError "TODO - path from request")
                                                |> (\response ->
                                                        case response of
                                                            Ok (Just okResponse) ->
                                                                { body = okResponse
                                                                , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                , statusCode = 200
                                                                }
                                                                    |> ToJsPayload.SendApiResponse
                                                                    |> Effect.SendSinglePage True

                                                            Ok Nothing ->
                                                                { body = Json.Encode.string "Hello1!"
                                                                , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                , statusCode = 404
                                                                }
                                                                    |> ToJsPayload.SendApiResponse
                                                                    |> Effect.SendSinglePage True

                                                            Err error ->
                                                                [ error ]
                                                                    |> ToJsPayload.Errors
                                                                    |> Effect.SendSinglePage True
                                                   )

                                        RenderRequest.Page payload ->
                                            let
                                                pageFoundResult : Result BuildError (Maybe NotFoundReason)
                                                pageFoundResult =
                                                    StaticHttpRequest.resolve ApplicationType.Cli
                                                        (if model.isDevServer then
                                                            config.handleRoute payload.frontmatter

                                                         else
                                                            DataSource.succeed Nothing
                                                        )
                                                        model.allRawResponses
                                                        |> Result.mapError (StaticHttpRequest.toBuildError (payload.path |> Path.toAbsolute))
                                            in
                                            case pageFoundResult of
                                                Ok Nothing ->
                                                    let
                                                        currentUrl : Url.Url
                                                        currentUrl =
                                                            { protocol = Url.Https
                                                            , host = site.canonicalUrl
                                                            , port_ = Nothing
                                                            , path = payload.path |> Path.toRelative
                                                            , query = Nothing
                                                            , fragment = Nothing
                                                            }

                                                        staticData : Dict String String
                                                        staticData =
                                                            -- TODO this is causing the bug with loading for Site.elm!
                                                            --toJsPayload.pages
                                                            --    |> Dict.get (Path.toRelative page)
                                                            --    |> Maybe.withDefault Dict.empty
                                                            Dict.empty

                                                        pageDataResult : Result BuildError (PageServerResponse pageData)
                                                        pageDataResult =
                                                            StaticHttpRequest.resolve ApplicationType.Cli
                                                                (config.data (config.urlToRoute currentUrl))
                                                                (staticData |> Dict.map (\_ v -> Just v))
                                                                |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                                                        sharedDataResult : Result BuildError sharedData
                                                        sharedDataResult =
                                                            StaticHttpRequest.resolve ApplicationType.Cli
                                                                config.sharedData
                                                                (staticData |> Dict.map (\_ v -> Just v))
                                                                |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                                                        siteDataResult : Result BuildError siteData
                                                        siteDataResult =
                                                            StaticHttpRequest.resolve ApplicationType.Cli
                                                                site.data
                                                                (staticData |> Dict.map (\_ v -> Just v))
                                                                |> Result.mapError (StaticHttpRequest.toBuildError "Site.elm")
                                                    in
                                                    case
                                                        Result.map2 Tuple.pair pageDataResult sharedDataResult
                                                    of
                                                        Ok ( pageData__, sharedData__ ) ->
                                                            case pageData__ of
                                                                PageServerResponse.RenderPage responseInfo pageData ->
                                                                    let
                                                                        byteEncodedPageData : Bytes
                                                                        byteEncodedPageData =
                                                                            if True then
                                                                                -- TODO want to encode both shared and page data in dev server and HTML-embedded data
                                                                                -- but not for writing out the content.dat files - would be good to optimize this redundant data out
                                                                                --if model.isDevServer then
                                                                                ResponseSketch.HotUpdate pageData
                                                                                    sharedData__
                                                                                    |> config.encodeResponse
                                                                                    |> Bytes.Encode.encode

                                                                            else
                                                                                pageData
                                                                                    |> ResponseSketch.RenderPage
                                                                                    |> config.encodeResponse
                                                                                    |> Bytes.Encode.encode
                                                                    in
                                                                    case includeHtml of
                                                                        RenderRequest.OnlyJson ->
                                                                            { route = payload.path |> Path.toRelative
                                                                            , contentJson = Dict.empty
                                                                            , html = "This page was not rendered because it is a JSON-only request."
                                                                            , errors = []
                                                                            , head = []
                                                                            , title = "This page was not rendered because it is a JSON-only request."
                                                                            , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                            , is404 = False
                                                                            , statusCode = responseInfo.statusCode
                                                                            , headers = responseInfo.headers
                                                                            }
                                                                                |> ToJsPayload.PageProgress
                                                                                |> Effect.SendSinglePageNew False byteEncodedPageData

                                                                        RenderRequest.HtmlAndJson ->
                                                                            let
                                                                                currentPage : { path : Path, route : route }
                                                                                currentPage =
                                                                                    { path = payload.path, route = config.urlToRoute currentUrl }

                                                                                pageModel : userModel
                                                                                pageModel =
                                                                                    config.init
                                                                                        Pages.Flags.PreRenderFlags
                                                                                        sharedData__
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
                                                                                    (config.view currentPage Nothing sharedData__ pageData |> .view) pageModel
                                                                            in
                                                                            { route = payload.path |> Path.toRelative
                                                                            , contentJson = Dict.empty
                                                                            , html = viewValue.body |> HtmlPrinter.htmlToString
                                                                            , errors = []
                                                                            , head = config.view currentPage Nothing sharedData__ pageData |> .head
                                                                            , title = viewValue.title
                                                                            , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                            , is404 = False
                                                                            , statusCode = responseInfo.statusCode
                                                                            , headers = responseInfo.headers
                                                                            }
                                                                                |> ToJsPayload.PageProgress
                                                                                |> Effect.SendSinglePageNew False byteEncodedPageData

                                                                PageServerResponse.ServerResponse serverResponse ->
                                                                    { body = serverResponse |> PageServerResponse.toJson
                                                                    , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                    , statusCode = 200
                                                                    }
                                                                        |> ToJsPayload.SendApiResponse
                                                                        |> Effect.SendSinglePage True

                                                        Err error ->
                                                            [ error ] |> ToJsPayload.Errors |> Effect.SendSinglePage True

                                                Ok (Just notFoundReason) ->
                                                    render404Page config model payload.path notFoundReason

                                                Err error ->
                                                    [ error ] |> ToJsPayload.Errors |> Effect.SendSinglePage True

                                        RenderRequest.NotFound path ->
                                            render404Page config model path Pages.Internal.NotFoundReason.NoMatchingRoute
                    in
                    ( { model | staticRoutes = Just [] }
                    , apiResponse
                    )

                StaticResponses.Page contentJson ->
                    let
                        currentUrl : Url.Url
                        currentUrl =
                            { protocol = Url.Https
                            , host = site.canonicalUrl
                            , port_ = Nothing
                            , path = "TODO" --payload.path |> Path.toRelative
                            , query = Nothing
                            , fragment = Nothing
                            }

                        routeResult : Result BuildError route
                        routeResult =
                            model.staticRoutes
                                |> Maybe.map (List.map Tuple.second)
                                |> Maybe.andThen List.head
                                -- TODO is it possible to remove the Maybe here?
                                |> Result.fromMaybe (StaticHttpRequest.toBuildError "TODO url" (StaticHttpRequest.DecoderError "Expected route"))

                        pageDataResult : Result BuildError (PageServerResponse pageData)
                        pageDataResult =
                            routeResult
                                |> Result.andThen
                                    (\route ->
                                        StaticHttpRequest.resolve ApplicationType.Cli
                                            (config.data route)
                                            (contentJson |> Dict.map (\_ v -> Just v))
                                            |> Result.mapError (StaticHttpRequest.toBuildError "TODO url")
                                    )
                    in
                    case model.unprocessedPages |> List.head of
                        Just pageAndMetadata ->
                            ( model
                            , sendSinglePageProgress site contentJson config model pageAndMetadata
                            )

                        Nothing ->
                            let
                                byteEncodedPageData : Bytes
                                byteEncodedPageData =
                                    case pageDataResult of
                                        Ok pageServerResponse ->
                                            case pageServerResponse of
                                                PageServerResponse.RenderPage _ pageData ->
                                                    pageData
                                                        |> ResponseSketch.RenderPage
                                                        |> config.encodeResponse
                                                        |> Bytes.Encode.encode

                                                PageServerResponse.ServerResponse _ ->
                                                    -- TODO handle error?
                                                    Bytes.Encode.encode (Bytes.Encode.unsignedInt8 0)

                                        _ ->
                                            -- TODO handle error?
                                            Bytes.Encode.encode (Bytes.Encode.unsignedInt8 0)
                            in
                            ( model
                            , [] |> ToJsPayload.Errors |> Effect.SendSinglePageNew True byteEncodedPageData
                            )

                StaticResponses.Errors errors ->
                    ( model
                    , errors |> ToJsPayload.Errors |> Effect.SendSinglePage True
                    )


sendSinglePageProgress :
    SiteConfig siteData
    -> Dict String String
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model route
    -> ( Path, route )
    -> Effect
sendSinglePageProgress site contentJson config model =
    \( page, route ) ->
        case model.maybeRequestJson of
            RenderRequest.SinglePage includeHtml _ _ ->
                let
                    pageFoundResult : Result BuildError (Maybe NotFoundReason)
                    pageFoundResult =
                        StaticHttpRequest.resolve ApplicationType.Cli
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
                        StaticHttpRequest.resolve ApplicationType.Cli
                            (config.data (config.urlToRoute currentUrl))
                            (contentJson |> Dict.map (\_ v -> Just v))
                            |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                    sharedDataResult : Result BuildError sharedData
                    sharedDataResult =
                        StaticHttpRequest.resolve ApplicationType.Cli
                            config.sharedData
                            (contentJson |> Dict.map (\_ v -> Just v))
                            |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                    siteDataResult : Result BuildError siteData
                    siteDataResult =
                        StaticHttpRequest.resolve ApplicationType.Cli
                            site.data
                            (contentJson |> Dict.map (\_ v -> Just v))
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

                                                            PageServerResponse.ServerResponse _ ->
                                                                -- TODO handle error?
                                                                Bytes.Encode.encode (Bytes.Encode.unsignedInt8 0)

                                                    _ ->
                                                        -- TODO handle error?
                                                        Bytes.Encode.encode (Bytes.Encode.unsignedInt8 0)
                                        in
                                        { route = page |> Path.toRelative
                                        , contentJson = Dict.empty
                                        , html = rendered.view
                                        , errors = []
                                        , head = rendered.head ++ site.head siteData
                                        , title = rendered.title
                                        , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                        , is404 = False
                                        , statusCode = responseInfo.statusCode
                                        , headers = responseInfo.headers
                                        }
                                            |> ToJsPayload.PageProgress
                                            |> Effect.SendSinglePageNew True byteEncodedPageData

                                    PageServerResponse.ServerResponse serverResponse ->
                                        { body = serverResponse |> PageServerResponse.toJson
                                        , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                        , statusCode = 200
                                        }
                                            |> ToJsPayload.SendApiResponse
                                            |> Effect.SendSinglePage True

                            Just notFoundReason ->
                                render404Page config model page notFoundReason

                    Err error ->
                        [ error ]
                            |> ToJsPayload.Errors
                            |> Effect.SendSinglePage True


render404Page :
    ProgramConfig userMsg userModel route siteData pageData sharedData
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
                |> Pages.Internal.NotFoundReason.document config.pathPatterns

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
    , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
    , is404 = True
    , statusCode = 404
    , headers = []
    }
        |> ToJsPayload.PageProgress
        |> Effect.SendSinglePageNew True byteEncodedPageData
