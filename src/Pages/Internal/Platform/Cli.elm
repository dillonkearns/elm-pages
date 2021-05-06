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
import ElmHtml.InternalTypes exposing (decodeElmHtml)
import ElmHtml.ToString exposing (FormatOptions, defaultFormatOptions, nodeToStringWithOptions)
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Http
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import Pages.Internal.Platform.StaticResponses as StaticResponses exposing (StaticResponses)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsSuccessPayload)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttpRequest as StaticHttpRequest
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
    , mode : Mode
    , pendingRequests : List { masked : RequestDetails, unmasked : RequestDetails }
    , unprocessedPages : List ( PagePath, route )
    , staticRoutes : Maybe (List ( PagePath, route ))
    , maybeRequestJson : RenderRequest route
    }


type Msg
    = GotStaticHttpResponse { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result Pages.Http.Error String }
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
        contentCache =
            ContentCache.init Nothing
    in
    Platform.worker
        { init =
            \flags ->
                let
                    renderRequest =
                        Decode.decodeValue (RenderRequest.decoder config) flags
                            |> Result.withDefault RenderRequest.FullBuild
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

                                                    "GotGlob" ->
                                                        Decode.field "data"
                                                            (Decode.map2 Tuple.pair
                                                                (Decode.field "pattern" Decode.string)
                                                                (Decode.field "result" Decode.value)
                                                            )
                                                            |> Decode.map GotGlob

                                                    _ ->
                                                        Decode.fail "Unhandled msg"
                                            )
                            in
                            Decode.decodeValue decoder jsonValue
                                |> Result.mapError Decode.errorToString
                                |> Result.withDefault Continue
                        )
        }



--gotStaticFileDecoder : Decode.Decoder Msg


gotStaticFileDecoder =
    Decode.field "data"
        (Decode.map2 Tuple.pair
            (Decode.field "filePath" Decode.string)
            Decode.value
        )


viewRenderer : Html msg -> String
viewRenderer html =
    let
        options =
            { defaultFormatOptions | newLines = False, indent = 0 }
    in
    viewDecoder options html


viewDecoder : FormatOptions -> Html msg -> String
viewDecoder options viewHtml =
    case
        Decode.decodeValue
            (decodeElmHtml (\_ _ -> Decode.succeed ()))
            (asJsonView viewHtml)
    of
        Ok str ->
            nodeToStringWithOptions options str

        Err err ->
            "Error: " ++ Decode.errorToString err


asJsonView : Html msg -> Decode.Value
asJsonView x =
    Json.Encode.string "REPLACE_ME_WITH_JSON_STRINGIFY"



--perform : RenderRequest route -> ProgramConfig userMsg userModel route siteData pageData sharedData -> (Json.Encode.Value -> Cmd Msg) -> Effect -> Cmd Msg


perform :
    RenderRequest route
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> (Codec.Value -> Cmd Never)
    -> Effect
    -> Cmd Msg
perform renderRequest config toJsPort effect =
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
                    filePath =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.ReadFile filePath
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                    |> toJsPort
                    |> Cmd.map never

            else if unmasked.url |> String.startsWith "glob://" then
                let
                    globPattern =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.Glob globPattern
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                    |> toJsPort
                    |> Cmd.map never

            else
                Cmd.batch
                    [ Http.request
                        { method = unmasked.method
                        , url = unmasked.url
                        , headers = unmasked.headers |> List.map (\( key, value ) -> Http.header key value)
                        , body =
                            case unmasked.body of
                                StaticHttpBody.EmptyBody ->
                                    Http.emptyBody

                                StaticHttpBody.StringBody contentType string ->
                                    Http.stringBody contentType string

                                StaticHttpBody.JsonBody value ->
                                    Http.jsonBody value
                        , expect =
                            Pages.Http.expectString
                                (\response ->
                                    GotStaticHttpResponse
                                        { request = requests
                                        , response = response
                                        }
                                )
                        , timeout = Nothing
                        , tracker = Nothing
                        }
                    , toJsPort
                        (Json.Encode.object
                            [ ( "command", Json.Encode.string "log" )
                            , ( "value", Json.Encode.string ("Fetching " ++ masked.url) )
                            ]
                        )
                        |> Cmd.map never
                    ]

        Effect.SendSinglePage done info ->
            let
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
        , mode : Mode
        , staticHttpCache : Dict String (Maybe String)
        }
flagsDecoder =
    Decode.map3
        (\secrets mode staticHttpCache ->
            { secrets = secrets
            , mode = mode
            , staticHttpCache = staticHttpCache
            }
        )
        (Decode.field "secrets" SecretsDict.decoder)
        (Decode.field "mode" Mode.modeDecoder)
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
        Ok { secrets, mode, staticHttpCache } ->
            initLegacy renderRequest { secrets = secrets, mode = mode, staticHttpCache = staticHttpCache } contentCache config flags

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
                , mode = Mode.Dev
                , pendingRequests = []
                , unprocessedPages = []
                , staticRoutes = Just []
                , maybeRequestJson = renderRequest
                }


initLegacy :
    RenderRequest route
    -> { a | secrets : SecretsDict, mode : Mode, staticHttpCache : Dict String (Maybe String) }
    -> ContentCache
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Decode.Value
    -> ( Model route, Effect )
initLegacy renderRequest { secrets, mode, staticHttpCache } contentCache config flags =
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

                        RenderRequest.Api ( path, apiRequest ) ->
                            StaticResponses.renderApiRequest config
                                (apiRequest.matchesToResponse path)

                        RenderRequest.NotFound ->
                            StaticResponses.renderApiRequest config
                                (DataSource.succeed [])

                RenderRequest.FullBuild ->
                    StaticResponses.init config

        unprocessedPages =
            case renderRequest of
                RenderRequest.SinglePage _ serverRequestPayload _ ->
                    case serverRequestPayload of
                        RenderRequest.Page pageData ->
                            [ ( pageData.path, pageData.frontmatter ) ]

                        RenderRequest.Api _ ->
                            []

                        RenderRequest.NotFound ->
                            []

                RenderRequest.FullBuild ->
                    []

        unprocessedPagesState =
            case renderRequest of
                RenderRequest.SinglePage _ serverRequestPayload _ ->
                    case serverRequestPayload of
                        RenderRequest.Page pageData ->
                            Just [ ( pageData.path, pageData.frontmatter ) ]

                        RenderRequest.Api _ ->
                            Nothing

                        RenderRequest.NotFound ->
                            Just []

                RenderRequest.FullBuild ->
                    Nothing

        initialModel =
            { staticResponses = staticResponses
            , secrets = secrets
            , errors = []
            , allRawResponses = staticHttpCache
            , mode = mode
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
                updatedModel =
                    (case response of
                        Ok _ ->
                            { model
                                | pendingRequests =
                                    model.pendingRequests
                                        |> List.filter (\pending -> pending /= request)
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
                updatedModel =
                    model
            in
            StaticResponses.nextStep config
                updatedModel
                Nothing
                |> nextStepToEffect contentCache config updatedModel

        GotGlob ( globPattern, globResult ) ->
            let
                --_ =
                --    Debug.log "GotStaticFile"
                --        { filePath = filePath
                --        , pendingRequests = model.pendingRequests
                --        }
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
                nextAndPending =
                    model.pendingRequests ++ httpRequests

                doNow =
                    nextAndPending

                pending =
                    []

                updatedRoutes =
                    case maybeRoutes of
                        Just newRoutes ->
                            newRoutes
                                |> List.map
                                    (\route ->
                                        ( PagePath.build (config.routeToPath route)
                                        , route
                                        )
                                    )
                                |> Just

                        Nothing ->
                            model.staticRoutes

                updatedUnprocessedPages =
                    case maybeRoutes of
                        Just newRoutes ->
                            newRoutes
                                |> List.map
                                    (\route ->
                                        ( PagePath.build (config.routeToPath route)
                                        , route
                                        )
                                    )

                        Nothing ->
                            model.unprocessedPages

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
            case model.mode of
                Mode.ElmToHtmlBeta ->
                    let
                        sendManifestIfNeeded =
                            if
                                List.length model.unprocessedPages
                                    == (model.staticRoutes
                                            |> Maybe.map List.length
                                            |> Maybe.withDefault -1
                                       )
                            then
                                case toJsPayload of
                                    ToJsPayload.Success value ->
                                        Effect.SendSinglePage True
                                            (ToJsPayload.InitialData
                                                { filesToGenerate = value.filesToGenerate
                                                }
                                            )

                                    ToJsPayload.Errors _ ->
                                        Effect.SendJsData toJsPayload

                                    ToJsPayload.ApiResponse ->
                                        let
                                            apiResponse : Effect
                                            apiResponse =
                                                case model.maybeRequestJson of
                                                    RenderRequest.SinglePage includeHtml requestPayload value ->
                                                        case requestPayload of
                                                            RenderRequest.Api ( path, apiHandler ) ->
                                                                let
                                                                    thing : DataSource (Maybe ApiRoute.Response)
                                                                    thing =
                                                                        apiHandler.matchesToResponse path
                                                                in
                                                                StaticHttpRequest.resolve ApplicationType.Browser
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
                                                                                    { body = "Not found"
                                                                                    , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                                    , statusCode = 404
                                                                                    }
                                                                                        |> ToJsPayload.SendApiResponse
                                                                                        |> Effect.SendSinglePage True

                                                                                Err error ->
                                                                                    [ error ] |> ToJsPayload.Errors |> Effect.SendJsData
                                                                       )

                                                            RenderRequest.Page _ ->
                                                                [] |> ToJsPayload.Errors |> Effect.SendJsData

                                                            RenderRequest.NotFound ->
                                                                { body = "Not found"
                                                                , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                                , statusCode = 404
                                                                }
                                                                    |> ToJsPayload.SendApiResponse
                                                                    |> Effect.SendSinglePage True

                                                    RenderRequest.FullBuild ->
                                                        [] |> ToJsPayload.Errors |> Effect.SendJsData
                                        in
                                        apiResponse

                            else
                                Effect.NoEffect
                    in
                    case toJsPayload of
                        ToJsPayload.ApiResponse ->
                            let
                                apiResponse : Effect
                                apiResponse =
                                    case model.maybeRequestJson of
                                        RenderRequest.SinglePage includeHtml requestPayload value ->
                                            case requestPayload of
                                                RenderRequest.Api ( path, apiHandler ) ->
                                                    let
                                                        thing : DataSource (Maybe ApiRoute.Response)
                                                        thing =
                                                            apiHandler.matchesToResponse path
                                                    in
                                                    StaticHttpRequest.resolve ApplicationType.Browser
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
                                                                        { body = "Not found"
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

                                                RenderRequest.Page _ ->
                                                    [] |> ToJsPayload.Errors |> Effect.SendJsData

                                                RenderRequest.NotFound ->
                                                    { body = "Not found"
                                                    , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                                                    , statusCode = 404
                                                    }
                                                        |> ToJsPayload.SendApiResponse
                                                        |> Effect.SendSinglePage True

                                        RenderRequest.FullBuild ->
                                            [] |> ToJsPayload.Errors |> Effect.SendJsData
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

                                            ToJsPayload.Errors _ ->
                                                Nothing

                                            ToJsPayload.ApiResponse ->
                                                Nothing
                                    )
                                |> (\cmds ->
                                        ( model
                                            |> popProcessedRequest
                                        , Effect.Batch
                                            (sendManifestIfNeeded
                                                :: cmds
                                            )
                                        )
                                   )

                _ ->
                    ( model, Effect.SendJsData toJsPayload )


sendSinglePageProgress :
    ToJsSuccessPayload
    -> ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model route
    -> ( PagePath, route )
    -> Effect
sendSinglePageProgress toJsPayload config model =
    \( page, route ) ->
        case model.maybeRequestJson of
            RenderRequest.SinglePage includeHtml _ _ ->
                let
                    pageFoundResult =
                        StaticHttpRequest.resolve ApplicationType.Browser
                            (config.handleRoute route)
                            model.allRawResponses
                            |> Result.mapError (StaticHttpRequest.toBuildError currentUrl.path)

                    allRoutes =
                        []

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
                                                            }
                                                        )
                                                        |> Tuple.first

                                                viewValue : { title : String, body : Html userMsg }
                                                viewValue =
                                                    (config.view currentPage sharedData pageData |> .view) pageModel
                                            in
                                            { head = config.view currentPage sharedData pageData |> .head
                                            , view = viewValue.body |> viewRenderer
                                            , title = viewValue.title
                                            }
                                        )

                    currentUrl =
                        { protocol = Url.Https
                        , host = config.site allRoutes |> .canonicalUrl
                        , port_ = Nothing
                        , path = page |> PagePath.toString
                        , query = Nothing
                        , fragment = Nothing
                        }

                    staticData : Dict String String
                    staticData =
                        toJsPayload.pages
                            |> Dict.get (PagePath.toString page)
                            |> Maybe.withDefault Dict.empty

                    currentPage : { path : PagePath, frontmatter : route }
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
                in
                case Result.map2 Tuple.pair pageFoundResult renderedResult of
                    Ok ( pageFound, rendered ) ->
                        { route = page |> PagePath.toString
                        , contentJson =
                            toJsPayload.pages
                                |> Dict.get (PagePath.toString page)
                                |> Maybe.withDefault Dict.empty
                        , html = rendered.view
                        , errors = []
                        , head = rendered.head
                        , title = rendered.title
                        , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                        , is404 = not pageFound
                        }
                            |> sendProgress

                    Err error ->
                        [ error ]
                            |> ToJsPayload.Errors
                            |> Effect.SendJsData

            RenderRequest.FullBuild ->
                let
                    staticData : Dict String String
                    staticData =
                        toJsPayload.pages
                            |> Dict.get (PagePath.toString page)
                            |> Maybe.withDefault Dict.empty

                    currentPage : { path : PagePath, frontmatter : route }
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

                    allRoutes =
                        -- TODO
                        []

                    currentUrl =
                        { protocol = Url.Https
                        , host = config.site allRoutes |> .canonicalUrl
                        , port_ = Nothing
                        , path = page |> PagePath.toString
                        , query = Nothing
                        , fragment = Nothing
                        }
                in
                case Result.map2 Tuple.pair sharedDataResult pageDataResult of
                    Ok ( sharedData, pageData ) ->
                        let
                            pageModel : userModel
                            pageModel =
                                config.init
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
                                        }
                                    )
                                    |> Tuple.first

                            viewValue : { title : String, body : Html userMsg }
                            viewValue =
                                (config.view currentPage sharedData pageData |> .view) pageModel

                            headTags : List Head.Tag
                            headTags =
                                config.view currentPage sharedData pageData |> .head
                        in
                        { route = page |> PagePath.toString
                        , contentJson =
                            toJsPayload.pages
                                |> Dict.get (PagePath.toString page)
                                |> Maybe.withDefault Dict.empty
                        , html = viewValue.body |> viewRenderer
                        , errors = []
                        , head = headTags
                        , title = viewValue.title
                        , staticHttpCache = model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
                        , is404 = False
                        }
                            |> sendProgress

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
