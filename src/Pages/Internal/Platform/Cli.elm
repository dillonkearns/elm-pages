module Pages.Internal.Platform.Cli exposing
    ( Flags
    , Model
    , Msg(..)
    , Program
    , cliApplication
    , init
    , update
    )

import ApiRoute
import BuildError exposing (BuildError)
import Codec
import DataSource exposing (DataSource)
import DataSource.Http exposing (RequestDetails)
import Dict exposing (Dict)
import Dict.Extra
import Head
import Html exposing (Html)
import HtmlPrinter
import Http
import Internal.ApiRoute exposing (Done(..))
import Json.Decode as Decode
import Json.Encode
import NotFoundReason exposing (NotFoundReason)
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Flags
import Pages.Http
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.StaticResponses as StaticResponses exposing (StaticResponses)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsSuccessPayload)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttp.Request
import Pages.StaticHttpRequest as StaticHttpRequest
import Path exposing (Path)
import RenderRequest exposing (RenderRequest)
import SecretsDict exposing (SecretsDict)
import Task
import TerminalText as Terminal
import Url


type alias Flags =
    Decode.Value


type alias Model route =
    { staticResponses : StaticResponses
    , secrets : SecretsDict
    , errors : List BuildError
    , allRawResponses : Dict String (Maybe String)
    , pendingRequests : List { masked : RequestDetails, unmasked : RequestDetails }
    , unprocessedPages : List ( Path, route )
    , staticRoutes : Maybe (List ( Path, route ))
    , maybeRequestJson : RenderRequest route
    }


type Msg
    = GotStaticHttpResponse { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result Pages.Http.Error String }
    | GotPortResponse ( String, Decode.Value )
    | GotStaticFile ( String, Decode.Value )
    | GotBuildError BuildError
    | GotGlob ( String, Decode.Value )
    | Continue


type alias Program route =
    Platform.Program Flags (Model route) Msg


cliApplication :
    ProgramConfig userMsg userModel (Maybe route) siteData pageData sharedData
    -> Program (Maybe route)
cliApplication config =
    let
        contentCache : ContentCache
        contentCache =
            ContentCache.init Nothing
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
                init renderRequest contentCache config flags
                    |> Tuple.mapSecond (perform renderRequest config config.toJsPort)
        , update =
            \msg model ->
                update contentCache config msg model
                    |> Tuple.mapSecond (perform model.maybeRequestJson config config.toJsPort)
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
                                                            (Decode.field "filePath" Decode.string
                                                                |> Decode.map
                                                                    (\filePath ->
                                                                        { title = "File not found"
                                                                        , message =
                                                                            [ Terminal.text "A DataSource.File read failed because I couldn't find this file: "
                                                                            , Terminal.yellow <| Terminal.text filePath
                                                                            ]
                                                                        , fatal = True
                                                                        , path = "" -- TODO wire in current path here
                                                                        }
                                                                    )
                                                            )
                                                            |> Decode.map GotBuildError

                                                    "GotFile" ->
                                                        gotStaticFileDecoder
                                                            |> Decode.map GotStaticFile

                                                    "GotPort" ->
                                                        gotPortDecoder
                                                            |> Decode.map GotPortResponse

                                                    "GotGlob" ->
                                                        Decode.field "data"
                                                            (Decode.map2 Tuple.pair
                                                                (Decode.field "pattern" Decode.string)
                                                                (Decode.field "result" Decode.value)
                                                            )
                                                            |> Decode.map GotGlob

                                                    "GotHttp" ->
                                                        Decode.field "data"
                                                            (Decode.map2
                                                                (\requests response ->
                                                                    GotStaticHttpResponse
                                                                        { request =
                                                                            { masked = requests.masked
                                                                            , unmasked = requests.unmasked
                                                                            }
                                                                        , response = Ok response
                                                                        }
                                                                )
                                                                (Decode.field "request" requestDecoder)
                                                                (Decode.field "result" Decode.string)
                                                            )

                                                    _ ->
                                                        Decode.fail "Unhandled msg"
                                            )
                            in
                            Decode.decodeValue decoder jsonValue
                                |> Result.mapError Decode.errorToString
                                |> Result.withDefault Continue
                        )
        }


requestDecoder : Decode.Decoder { masked : Pages.StaticHttp.Request.Request, unmasked : Pages.StaticHttp.Request.Request }
requestDecoder =
    (Codec.object (\masked unmasked -> { masked = masked, unmasked = unmasked })
        |> Codec.field "masked" .masked Pages.StaticHttp.Request.codec
        |> Codec.field "unmasked" .unmasked Pages.StaticHttp.Request.codec
        |> Codec.buildObject
    )
        |> Codec.decoder


gotStaticFileDecoder : Decode.Decoder ( String, Decode.Value )
gotStaticFileDecoder =
    Decode.field "data"
        (Decode.map2 Tuple.pair
            (Decode.field "filePath" Decode.string)
            Decode.value
        )


gotPortDecoder : Decode.Decoder ( String, Decode.Value )
gotPortDecoder =
    Decode.field "data"
        (Decode.map2 Tuple.pair
            (Decode.field "portName" Decode.string)
            (Decode.field "portResponse" Decode.value)
        )


perform :
    RenderRequest route
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> (Codec.Value -> Cmd Never)
    -> Effect
    -> Cmd Msg
perform renderRequest config toJsPort effect =
    -- elm-review: known-unoptimized-recursion
    let
        canonicalSiteUrl : String
        canonicalSiteUrl =
            config.site [] |> .canonicalUrl
    in
    case effect of
        Effect.NoEffect ->
            Cmd.none

        Effect.SendJsData value ->
            value
                |> Codec.encoder ToJsPayload.toJsCodec
                |> toJsPort
                |> Cmd.map never

        Effect.Batch list ->
            list
                |> List.map (perform renderRequest config toJsPort)
                |> Cmd.batch

        Effect.FetchHttp ({ unmasked, masked } as requests) ->
            if unmasked.url == "$$elm-pages$$headers" then
                Cmd.batch
                    [ Task.succeed
                        { request = requests
                        , response =
                            renderRequest
                                |> RenderRequest.maybeRequestPayload
                                |> Maybe.map (Json.Encode.encode 0)
                                |> Result.fromMaybe (Pages.Http.BadUrl "$$elm-pages$$headers is only available on server-side request (not on build).")
                        }
                        |> Task.perform GotStaticHttpResponse
                    ]

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

            else if unmasked.url |> String.startsWith "port://" then
                let
                    portName : String
                    portName =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.Port portName
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                    |> toJsPort
                    |> Cmd.map never

            else
                ToJsPayload.DoHttp { masked = masked, unmasked = unmasked }
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
        { secrets : SecretsDict
        , staticHttpCache : Dict String (Maybe String)
        }
flagsDecoder =
    Decode.map2
        (\secrets staticHttpCache ->
            { secrets = secrets
            , staticHttpCache = staticHttpCache
            }
        )
        (Decode.field "secrets" SecretsDict.decoder)
        (Decode.field "staticHttpCache"
            (Decode.dict
                (Decode.string
                    |> Decode.map Just
                )
            )
        )


init :
    RenderRequest route
    -> ContentCache
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Decode.Value
    -> ( Model route, Effect )
init renderRequest contentCache config flags =
    case Decode.decodeValue flagsDecoder flags of
        Ok { secrets, staticHttpCache } ->
            initLegacy renderRequest { secrets = secrets, staticHttpCache = staticHttpCache } contentCache config flags

        Err error ->
            updateAndSendPortIfDone
                contentCache
                config
                { staticResponses = StaticResponses.error
                , secrets = SecretsDict.masked
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
                }


initLegacy :
    RenderRequest route
    -> { a | secrets : SecretsDict, staticHttpCache : Dict String (Maybe String) }
    -> ContentCache
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Decode.Value
    -> ( Model route, Effect )
initLegacy renderRequest { secrets, staticHttpCache } contentCache config flags =
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
                                (config.handleRoute serverRequestPayload.frontmatter)

                        RenderRequest.Api ( path, Done apiRequest ) ->
                            StaticResponses.renderApiRequest
                                (apiRequest.matchesToResponse path)

                        RenderRequest.NotFound path ->
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

                        RenderRequest.NotFound path ->
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

                        RenderRequest.NotFound path ->
                            Just []

        initialModel : Model route
        initialModel =
            { staticResponses = staticResponses
            , secrets = secrets
            , errors = []
            , allRawResponses = staticHttpCache
            , pendingRequests = []
            , unprocessedPages = unprocessedPages
            , staticRoutes = unprocessedPagesState
            , maybeRequestJson = renderRequest
            }
    in
    StaticResponses.nextStep config initialModel Nothing
        |> nextStepToEffect contentCache
            config
            initialModel


updateAndSendPortIfDone :
    ContentCache
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model route
    -> ( Model route, Effect )
updateAndSendPortIfDone contentCache config model =
    StaticResponses.nextStep
        config
        model
        Nothing
        |> nextStepToEffect contentCache config model


update :
    ContentCache
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Msg
    -> Model route
    -> ( Model route, Effect )
update contentCache config msg model =
    case msg of
        GotStaticHttpResponse { request, response } ->
            let
                updatedModel : Model route
                updatedModel =
                    (case response of
                        Ok _ ->
                            { model
                                | pendingRequests =
                                    model.pendingRequests
                                        |> List.filter
                                            (\pending ->
                                                pending /= request
                                            )
                            }

                        Err error ->
                            { model
                                | errors =
                                    List.append
                                        model.errors
                                        [ { title = "Static HTTP Error"
                                          , message =
                                                [ Terminal.text "I got an error making an HTTP request to this URL: "

                                                -- TODO include HTTP method, headers, and body
                                                , Terminal.yellow <| Terminal.text request.masked.url
                                                , Terminal.text <| Json.Encode.encode 2 <| StaticHttpBody.encode request.masked.body
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
                                                        Terminal.text <| "Invalid url: " ++ request.masked.url

                                                    Pages.Http.Timeout ->
                                                        Terminal.text "Timeout"

                                                    Pages.Http.NetworkError ->
                                                        Terminal.text "Network error"
                                                ]
                                          , fatal = True
                                          , path = "" -- TODO wire in current path here
                                          }
                                        ]
                            }
                    )
                        |> StaticResponses.update
                            -- TODO for hash pass in RequestDetails here
                            { request = request
                            , response = Result.mapError (\_ -> ()) response
                            }
            in
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect contentCache config updatedModel

        GotStaticFile ( filePath, fileContent ) ->
            let
                --_ =
                --    Debug.log "GotStaticFile"
                --        { filePath = filePath
                --        , pendingRequests = model.pendingRequests
                --        }
                updatedModel : Model route
                updatedModel =
                    { model
                        | pendingRequests =
                            model.pendingRequests
                                |> List.filter
                                    (\pending ->
                                        pending.unmasked.url
                                            == ("file://" ++ filePath)
                                    )
                    }
                        |> StaticResponses.update
                            -- TODO for hash pass in RequestDetails here
                            { request =
                                { masked =
                                    { url = "file://" ++ filePath
                                    , method = "GET"
                                    , headers = []
                                    , body = StaticHttpBody.EmptyBody
                                    }
                                , unmasked =
                                    { url = "file://" ++ filePath
                                    , method = "GET"
                                    , headers = []
                                    , body = StaticHttpBody.EmptyBody
                                    }
                                }
                            , response = Ok (Json.Encode.encode 0 fileContent)
                            }
            in
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect contentCache config updatedModel

        Continue ->
            let
                updatedModel : Model route
                updatedModel =
                    model
            in
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect contentCache config updatedModel

        GotGlob ( globPattern, globResult ) ->
            let
                updatedModel : Model route
                updatedModel =
                    { model
                        | pendingRequests =
                            model.pendingRequests
                                |> List.filter
                                    (\pending -> pending.unmasked.url == ("glob://" ++ globPattern))
                    }
                        |> StaticResponses.update
                            -- TODO for hash pass in RequestDetails here
                            { request =
                                { masked =
                                    { url = "glob://" ++ globPattern
                                    , method = "GET"
                                    , headers = []
                                    , body = StaticHttpBody.EmptyBody
                                    }
                                , unmasked =
                                    { url = "glob://" ++ globPattern
                                    , method = "GET"
                                    , headers = []
                                    , body = StaticHttpBody.EmptyBody
                                    }
                                }
                            , response = Ok (Json.Encode.encode 0 globResult)
                            }
            in
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect contentCache config updatedModel

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
                |> nextStepToEffect contentCache config updatedModel

        GotPortResponse ( portName, portResponse ) ->
            let
                updatedModel : Model route
                updatedModel =
                    { model
                        | pendingRequests =
                            model.pendingRequests
                                |> List.filter
                                    (\pending -> pending.unmasked.url == ("port://" ++ portName))
                    }
                        |> StaticResponses.update
                            -- TODO for hash pass in RequestDetails here
                            { request =
                                { masked =
                                    { url = "port://" ++ portName
                                    , method = "GET"
                                    , headers = []
                                    , body = StaticHttpBody.EmptyBody
                                    }
                                , unmasked =
                                    { url = "port://" ++ portName
                                    , method = "GET"
                                    , headers = []
                                    , body = StaticHttpBody.EmptyBody
                                    }
                                }
                            , response = Ok (Json.Encode.encode 0 portResponse)
                            }
            in
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect contentCache config updatedModel


nextStepToEffect :
    ContentCache
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model route
    -> ( StaticResponses, StaticResponses.NextStep route )
    -> ( Model route, Effect )
nextStepToEffect contentCache config model ( updatedStaticResponsesModel, nextStep ) =
    case nextStep of
        StaticResponses.Continue updatedAllRawResponses httpRequests maybeRoutes ->
            let
                nextAndPending : List { masked : RequestDetails, unmasked : RequestDetails }
                nextAndPending =
                    model.pendingRequests ++ httpRequests

                doNow : List { masked : RequestDetails, unmasked : RequestDetails }
                doNow =
                    nextAndPending

                pending : List { masked : RequestDetails, unmasked : RequestDetails }
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
                nextStepToEffect contentCache
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
                ToJsPayload.ApiResponse ->
                    let
                        apiResponse : Effect
                        apiResponse =
                            case model.maybeRequestJson of
                                RenderRequest.SinglePage includeHtml requestPayload value ->
                                    case requestPayload of
                                        RenderRequest.Api ( path, Done apiHandler ) ->
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
                                                                { body = okResponse.body
                                                                , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                , statusCode = 200
                                                                }
                                                                    |> ToJsPayload.SendApiResponse
                                                                    |> Effect.SendSinglePage True

                                                            Ok Nothing ->
                                                                { body = "Hello1!"
                                                                , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                , statusCode = 404
                                                                }
                                                                    |> ToJsPayload.SendApiResponse
                                                                    |> Effect.SendSinglePage True

                                                            Err error ->
                                                                [ error ]
                                                                    |> ToJsPayload.Errors
                                                                    |> Effect.SendJsData
                                                   )

                                        RenderRequest.Page payload ->
                                            let
                                                pageFoundResult : Result BuildError (Maybe NotFoundReason)
                                                pageFoundResult =
                                                    StaticHttpRequest.resolve ApplicationType.Browser
                                                        (config.handleRoute payload.frontmatter)
                                                        model.allRawResponses
                                                        |> Result.mapError (StaticHttpRequest.toBuildError (payload.path |> Path.toAbsolute))
                                            in
                                            case pageFoundResult of
                                                Ok Nothing ->
                                                    let
                                                        allRoutes : List route
                                                        allRoutes =
                                                            []

                                                        currentUrl : Url.Url
                                                        currentUrl =
                                                            { protocol = Url.Https
                                                            , host = config.site [] |> .canonicalUrl
                                                            , port_ = Nothing
                                                            , path = payload.path |> Path.toRelative
                                                            , query = Nothing
                                                            , fragment = Nothing
                                                            }

                                                        renderedResult : Result BuildError { head : List Head.Tag, view : String, title : String }
                                                        renderedResult =
                                                            case includeHtml of
                                                                RenderRequest.OnlyJson ->
                                                                    Ok
                                                                        { head = []
                                                                        , view = "This page was not rendered because it is a JSON-only request."
                                                                        , title = "This page was not rendered because it is a JSON-only request."
                                                                        }

                                                                RenderRequest.HtmlAndJson ->
                                                                    Result.map2 Tuple.pair pageDataResult sharedDataResult
                                                                        |> Result.map
                                                                            (\( pageData, sharedData ) ->
                                                                                let
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
                                                                                                , metadata = currentPage.frontmatter
                                                                                                , pageUrl = Nothing
                                                                                                }
                                                                                            )
                                                                                            |> Tuple.first

                                                                                    viewValue : { title : String, body : Html userMsg }
                                                                                    viewValue =
                                                                                        (config.view currentPage Nothing sharedData pageData |> .view) pageModel
                                                                                in
                                                                                { head = config.view currentPage Nothing sharedData pageData |> .head
                                                                                , view = viewValue.body |> HtmlPrinter.htmlToString
                                                                                , title = viewValue.title
                                                                                }
                                                                            )

                                                        staticData : Dict String String
                                                        staticData =
                                                            --toJsPayload.pages
                                                            --    |> Dict.get (Path.toRelative page)
                                                            --    |> Maybe.withDefault Dict.empty
                                                            Dict.empty

                                                        currentPage : { path : Path, frontmatter : route }
                                                        currentPage =
                                                            { path = payload.path, frontmatter = config.urlToRoute currentUrl }

                                                        pageDataResult : Result BuildError pageData
                                                        pageDataResult =
                                                            StaticHttpRequest.resolve ApplicationType.Browser
                                                                (config.data (config.urlToRoute currentUrl))
                                                                (staticData |> Dict.map (\_ v -> Just v))
                                                                |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                                                        sharedDataResult : Result BuildError sharedData
                                                        sharedDataResult =
                                                            StaticHttpRequest.resolve ApplicationType.Browser
                                                                config.sharedData
                                                                (staticData |> Dict.map (\_ v -> Just v))
                                                                |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                                                        siteDataResult : Result BuildError siteData
                                                        siteDataResult =
                                                            StaticHttpRequest.resolve ApplicationType.Cli
                                                                (config.site allRoutes |> .data)
                                                                (staticData |> Dict.map (\_ v -> Just v))
                                                                |> Result.mapError (StaticHttpRequest.toBuildError "Site.elm")
                                                    in
                                                    case Result.map3 (\a b c -> ( a, b, c )) pageFoundResult renderedResult siteDataResult of
                                                        Ok ( pageFound, rendered, siteData ) ->
                                                            { route = payload.path |> Path.toRelative
                                                            , contentJson =
                                                                --toJsPayload.pages
                                                                --    |> Dict.get (Path.toRelative page)
                                                                --    |> Maybe.withDefault Dict.empty
                                                                Dict.empty
                                                            , html = rendered.view
                                                            , errors = []
                                                            , head = rendered.head
                                                            , title = rendered.title
                                                            , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                            , is404 = False
                                                            }
                                                                |> ToJsPayload.PageProgress
                                                                |> Effect.SendSinglePage False

                                                        Err error ->
                                                            [ error ] |> ToJsPayload.Errors |> Effect.SendJsData

                                                Ok (Just notFoundReason) ->
                                                    render404Page config model payload.path notFoundReason

                                                Err error ->
                                                    [] |> ToJsPayload.Errors |> Effect.SendJsData

                                        RenderRequest.NotFound path ->
                                            render404Page config model path NotFoundReason.NoMatchingRoute
                    in
                    ( { model | staticRoutes = Just [] }
                    , apiResponse
                    )

                _ ->
                    model.unprocessedPages
                        |> List.take 1
                        |> List.filterMap
                            (\pageAndMetadata ->
                                case toJsPayload of
                                    ToJsPayload.Success value ->
                                        sendSinglePageProgress value config model pageAndMetadata
                                            |> Just

                                    ToJsPayload.Errors errors ->
                                        errors |> ToJsPayload.Errors |> Effect.SendJsData |> Just

                                    ToJsPayload.ApiResponse ->
                                        Nothing
                            )
                        |> (\cmds ->
                                ( model
                                    |> popProcessedRequest
                                , Effect.Batch cmds
                                )
                           )


sendSinglePageProgress :
    ToJsSuccessPayload
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model route
    -> ( Path, route )
    -> Effect
sendSinglePageProgress toJsPayload config model =
    \( page, route ) ->
        case model.maybeRequestJson of
            RenderRequest.SinglePage includeHtml _ _ ->
                let
                    pageFoundResult : Result BuildError (Maybe NotFoundReason)
                    pageFoundResult =
                        StaticHttpRequest.resolve ApplicationType.Browser
                            (config.handleRoute route)
                            model.allRawResponses
                            |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                    allRoutes : List route
                    allRoutes =
                        []

                    renderedResult : Result BuildError { head : List Head.Tag, view : String, title : String }
                    renderedResult =
                        case includeHtml of
                            RenderRequest.OnlyJson ->
                                Ok
                                    { head = []
                                    , view = "This page was not rendered because it is a JSON-only request."
                                    , title = "This page was not rendered because it is a JSON-only request."
                                    }

                            RenderRequest.HtmlAndJson ->
                                Result.map2 Tuple.pair pageDataResult sharedDataResult
                                    |> Result.map
                                        (\( pageData, sharedData ) ->
                                            let
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
                                                            , metadata = currentPage.frontmatter
                                                            , pageUrl = Nothing
                                                            }
                                                        )
                                                        |> Tuple.first

                                                viewValue : { title : String, body : Html userMsg }
                                                viewValue =
                                                    (config.view currentPage Nothing sharedData pageData |> .view) pageModel
                                            in
                                            { head = config.view currentPage Nothing sharedData pageData |> .head
                                            , view = viewValue.body |> HtmlPrinter.htmlToString
                                            , title = viewValue.title
                                            }
                                        )

                    currentUrl : Url.Url
                    currentUrl =
                        { protocol = Url.Https
                        , host = config.site allRoutes |> .canonicalUrl
                        , port_ = Nothing
                        , path = page |> Path.toRelative
                        , query = Nothing
                        , fragment = Nothing
                        }

                    staticData : Dict String String
                    staticData =
                        toJsPayload.pages
                            |> Dict.get (Path.toRelative page)
                            |> Maybe.withDefault Dict.empty

                    currentPage : { path : Path, frontmatter : route }
                    currentPage =
                        { path = page, frontmatter = config.urlToRoute currentUrl }

                    pageDataResult : Result BuildError pageData
                    pageDataResult =
                        StaticHttpRequest.resolve ApplicationType.Browser
                            (config.data (config.urlToRoute currentUrl))
                            (staticData |> Dict.map (\_ v -> Just v))
                            |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                    sharedDataResult : Result BuildError sharedData
                    sharedDataResult =
                        StaticHttpRequest.resolve ApplicationType.Browser
                            config.sharedData
                            (staticData |> Dict.map (\_ v -> Just v))
                            |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                    siteDataResult : Result BuildError siteData
                    siteDataResult =
                        StaticHttpRequest.resolve ApplicationType.Cli
                            (config.site allRoutes |> .data)
                            (staticData |> Dict.map (\_ v -> Just v))
                            |> Result.mapError (StaticHttpRequest.toBuildError "Site.elm")
                in
                case Result.map3 (\a b c -> ( a, b, c )) pageFoundResult renderedResult siteDataResult of
                    Ok ( maybeNotFoundReason, rendered, siteData ) ->
                        case maybeNotFoundReason of
                            Nothing ->
                                { route = page |> Path.toRelative
                                , contentJson =
                                    toJsPayload.pages
                                        |> Dict.get (Path.toRelative page)
                                        |> Maybe.withDefault Dict.empty
                                , html = rendered.view
                                , errors = []
                                , head = rendered.head ++ (config.site allRoutes |> .head) siteData
                                , title = rendered.title
                                , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                , is404 = False
                                }
                                    |> sendProgress

                            Just notFoundReason ->
                                render404Page config model page notFoundReason

                    Err error ->
                        [ error ]
                            |> ToJsPayload.Errors
                            |> Effect.SendJsData


popProcessedRequest : Model route -> Model route
popProcessedRequest model =
    { model | unprocessedPages = List.drop 1 model.unprocessedPages }


sendProgress : ToJsPayload.ToJsSuccessPayloadNew -> Effect
sendProgress singlePage =
    singlePage |> ToJsPayload.PageProgress |> Effect.SendSinglePage False


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
                |> NotFoundReason.document config.pathPatterns
    in
    { route = Path.toAbsolute path
    , contentJson =
        Dict.fromList
            [ ( "notFoundReason"
              , Json.Encode.encode 0
                    (Codec.encoder NotFoundReason.codec
                        { path = path
                        , reason = notFoundReason
                        }
                    )
              )
            ]

    -- TODO include the needed info for content.json?
    , html = HtmlPrinter.htmlToString notFoundDocument.body
    , errors = []
    , head = []
    , title = notFoundDocument.title
    , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
    , is404 = True
    }
        |> ToJsPayload.PageProgress
        |> Effect.SendSinglePage True
