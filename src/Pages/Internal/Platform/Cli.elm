module Pages.Internal.Platform.Cli exposing
    ( Config
    , Flags
    , Model
    , Msg(..)
    , cliApplication
    , init
    , update
    )

import BuildError exposing (BuildError)
import Codec
import Dict exposing (Dict)
import ElmHtml.InternalTypes exposing (decodeElmHtml)
import ElmHtml.ToString exposing (FormatOptions, defaultFormatOptions, nodeToStringWithOptions)
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import NoMetadata exposing (NoMetadata)
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Http
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import Pages.Internal.Platform.StaticResponses as StaticResponses exposing (StaticResponses)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsSuccessPayload)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp exposing (RequestDetails)
import Pages.StaticHttpRequest as StaticHttpRequest
import SecretsDict exposing (SecretsDict)
import Task
import TerminalText as Terminal
import Url


type alias Flags =
    Decode.Value


type alias Model pathKey route =
    { staticResponses : StaticResponses
    , secrets : SecretsDict
    , errors : List BuildError
    , allRawResponses : Dict String (Maybe String)
    , mode : Mode
    , pendingRequests : List { masked : RequestDetails, unmasked : RequestDetails }
    , unprocessedPages : List ( PagePath pathKey, route )
    , staticRoutes : List ( PagePath pathKey, route )
    }


type Msg
    = GotStaticHttpResponse { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result Pages.Http.Error String }
    | GotStaticFile ( String, Decode.Value )
    | GotGlob ( String, Decode.Value )
    | Continue


type alias Config pathKey userMsg userModel route =
    { init :
        Maybe
            { path :
                { path : PagePath pathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            }
        -> ( userModel, Cmd userMsg )
    , getStaticRoutes : StaticHttp.Request (List route)
    , urlToRoute : Url.Url -> route
    , routeToPath : route -> List String
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : NoMetadata -> PagePath pathKey -> userModel -> Sub userMsg
    , view :
        List ( PagePath pathKey, NoMetadata )
        ->
            { path : PagePath pathKey
            , frontmatter : route
            }
        ->
            StaticHttp.Request
                { view : userModel -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , manifest : Manifest.Config pathKey
    , generateFiles :
        StaticHttp.Request
            (List
                (Result
                    String
                    { path : List String
                    , content : String
                    }
                )
            )
    , canonicalSiteUrl : String
    , pathKey : pathKey
    , onPageChange :
        Maybe
            ({ path : PagePath pathKey
             , query : Maybe String
             , fragment : Maybe String
             , metadata : route
             }
             -> userMsg
            )
    }


cliApplication :
    (Msg -> msg)
    -> (msg -> Maybe Msg)
    -> (Model pathKey route -> model)
    -> (model -> Maybe (Model pathKey route))
    -> Config pathKey userMsg userModel route
    -> Platform.Program Flags model msg
cliApplication cliMsgConstructor narrowMsg toModel fromModel config =
    let
        contentCache =
            ContentCache.init Nothing
    in
    Platform.worker
        { init =
            \flags ->
                init toModel contentCache config flags
                    |> Tuple.mapSecond (perform config cliMsgConstructor config.toJsPort)
        , update =
            \msg model ->
                case ( narrowMsg msg, fromModel model ) of
                    ( Just cliMsg, Just cliModel ) ->
                        update contentCache config cliMsg cliModel
                            |> Tuple.mapSecond (perform config cliMsgConstructor config.toJsPort)
                            |> Tuple.mapFirst toModel

                    _ ->
                        ( model, Cmd.none )
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
                                |> cliMsgConstructor
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


perform : Config pathKey userMsg userModel route -> (Msg -> msg) -> (Json.Encode.Value -> Cmd Never) -> Effect pathKey -> Cmd msg
perform config cliMsgConstructor toJsPort effect =
    case effect of
        Effect.NoEffect ->
            Cmd.none

        Effect.SendJsData value ->
            value
                |> Codec.encoder (ToJsPayload.toJsCodec config.canonicalSiteUrl)
                |> toJsPort
                |> Cmd.map never

        Effect.Batch list ->
            list
                |> List.map (perform config cliMsgConstructor toJsPort)
                |> Cmd.batch

        Effect.FetchHttp ({ unmasked, masked } as requests) ->
            -- let
            --     _ =
            --         Debug.log "Fetching" masked.url
            -- in
            if unmasked.url |> String.startsWith "file://" then
                let
                    filePath =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.ReadFile filePath
                    |> Codec.encoder (ToJsPayload.successCodecNew2 config.canonicalSiteUrl "")
                    |> toJsPort
                    |> Cmd.map never

            else if unmasked.url |> String.startsWith "glob://" then
                let
                    globPattern =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.Glob globPattern
                    |> Codec.encoder (ToJsPayload.successCodecNew2 config.canonicalSiteUrl "")
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
                                    (GotStaticHttpResponse >> cliMsgConstructor)
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

        Effect.SendSinglePage info ->
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
                    |> Codec.encoder (ToJsPayload.successCodecNew2 config.canonicalSiteUrl currentPagePath)
                    |> toJsPort
                    |> Cmd.map never
                , Task.succeed ()
                    |> Task.perform (\_ -> Continue)
                    |> Cmd.map cliMsgConstructor
                ]

        Effect.Continue ->
            Cmd.none

        Effect.ReadFile filePath ->
            ToJsPayload.ReadFile filePath
                |> Codec.encoder (ToJsPayload.successCodecNew2 config.canonicalSiteUrl "")
                |> toJsPort
                |> Cmd.map never

        Effect.GetGlob globPattern ->
            ToJsPayload.Glob globPattern
                |> Codec.encoder (ToJsPayload.successCodecNew2 config.canonicalSiteUrl "")
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
    (Model pathKey route -> model)
    -> ContentCache
    -> Config pathKey userMsg userModel route
    -> Decode.Value
    -> ( model, Effect pathKey )
init toModel contentCache config flags =
    case Decode.decodeValue flagsDecoder flags of
        Ok { secrets, mode, staticHttpCache } ->
            case mode of
                --Mode.ElmToHtmlBeta ->
                --    elmToHtmlBetaInit { secrets = secrets, mode = mode, staticHttpCache = staticHttpCache } toModel contentCache siteMetadata config flags
                --
                _ ->
                    initLegacy { secrets = secrets, mode = mode, staticHttpCache = staticHttpCache } toModel contentCache config

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
                      }
                    ]
                , allRawResponses = Dict.empty
                , mode = Mode.Dev
                , pendingRequests = []
                , unprocessedPages = []
                , staticRoutes = []
                }
                toModel



--)


initLegacy :
    { a | secrets : SecretsDict, mode : Mode, staticHttpCache : Dict String (Maybe String) }
    -> (Model pathKey route -> model)
    -> ContentCache
    -> Config pathKey userMsg userModel route
    -> ( model, Effect pathKey )
initLegacy { secrets, mode, staticHttpCache } toModel contentCache config =
    case contentCache of
        Ok _ ->
            let
                staticResponses : StaticResponses
                staticResponses =
                    StaticResponses.init config
            in
            StaticResponses.nextStep config mode secrets staticHttpCache [] staticResponses Nothing
                |> nextStepToEffect contentCache
                    config
                    { staticResponses = staticResponses
                    , secrets = secrets
                    , errors = []
                    , allRawResponses = staticHttpCache
                    , mode = mode
                    , pendingRequests = []
                    , unprocessedPages = []
                    , staticRoutes = []
                    }
                |> Tuple.mapFirst toModel

        Err metadataParserErrors ->
            updateAndSendPortIfDone
                contentCache
                config
                { staticResponses = StaticResponses.error
                , secrets = secrets
                , errors = metadataParserErrors |> List.map Tuple.second
                , allRawResponses = staticHttpCache
                , mode = mode
                , pendingRequests = []
                , unprocessedPages = []
                , staticRoutes = []
                }
                toModel


updateAndSendPortIfDone :
    ContentCache
    -> Config pathKey userMsg userModel route
    -> Model pathKey route
    -> (Model pathKey route -> model)
    -> ( model, Effect pathKey )
updateAndSendPortIfDone contentCache config model toModel =
    StaticResponses.nextStep
        config
        model.mode
        model.secrets
        model.allRawResponses
        model.errors
        model.staticResponses
        Nothing
        |> nextStepToEffect contentCache config model
        |> Tuple.mapFirst toModel



--, { model | unprocessedPages = List.drop 1 model.unprocessedPages }


update :
    ContentCache
    -> Config pathKey userMsg userModel route
    -> Msg
    -> Model pathKey route
    -> ( Model pathKey route, Effect pathKey )
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
                updatedModel.mode
                updatedModel.secrets
                updatedModel.allRawResponses
                updatedModel.errors
                updatedModel.staticResponses
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
                updatedModel.mode
                updatedModel.secrets
                updatedModel.allRawResponses
                updatedModel.errors
                updatedModel.staticResponses
                Nothing
                |> nextStepToEffect contentCache config updatedModel

        Continue ->
            -- TODO
            let
                --_ =
                --    Debug.log "Continuing..." (List.length model.unprocessedPages)
                updatedModel =
                    model
            in
            StaticResponses.nextStep config
                updatedModel.mode
                updatedModel.secrets
                updatedModel.allRawResponses
                updatedModel.errors
                updatedModel.staticResponses
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
                updatedModel.mode
                updatedModel.secrets
                updatedModel.allRawResponses
                updatedModel.errors
                updatedModel.staticResponses
                Nothing
                |> nextStepToEffect contentCache config updatedModel


nextStepToEffect :
    ContentCache
    -> Config pathKey userMsg userModel route
    -> Model pathKey route
    -> ( StaticResponses, StaticResponses.NextStep pathKey route )
    -> ( Model pathKey route, Effect pathKey )
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
                                        ( PagePath.build config.pathKey (config.routeToPath route)
                                        , route
                                        )
                                    )

                        Nothing ->
                            model.staticRoutes

                updatedUnprocessedPages =
                    case maybeRoutes of
                        Just newRoutes ->
                            newRoutes
                                |> List.map
                                    (\route ->
                                        ( PagePath.build config.pathKey (config.routeToPath route)
                                        , route
                                        )
                                    )

                        Nothing ->
                            model.unprocessedPages
            in
            ( { model
                | allRawResponses = updatedAllRawResponses
                , pendingRequests = pending
                , staticResponses = updatedStaticResponsesModel
                , staticRoutes = updatedRoutes
                , unprocessedPages = updatedUnprocessedPages
              }
            , doNow
                |> List.map Effect.FetchHttp
                |> Effect.Batch
            )

        StaticResponses.Finish toJsPayload ->
            case model.mode of
                Mode.ElmToHtmlBeta ->
                    let
                        sendManifestIfNeeded =
                            if List.length model.unprocessedPages == List.length model.staticRoutes then
                                case toJsPayload of
                                    ToJsPayload.Success value ->
                                        Effect.SendSinglePage
                                            (ToJsPayload.InitialData
                                                { manifest = value.manifest
                                                , filesToGenerate = value.filesToGenerate
                                                }
                                            )

                                    ToJsPayload.Errors _ ->
                                        Effect.SendJsData toJsPayload

                            else
                                Effect.NoEffect
                    in
                    model.unprocessedPages
                        |> List.take 1
                        |> List.filterMap
                            (\pageAndMetadata ->
                                case toJsPayload of
                                    ToJsPayload.Success value ->
                                        sendSinglePageProgress value config contentCache model pageAndMetadata
                                            |> Just

                                    ToJsPayload.Errors _ ->
                                        Nothing
                            )
                        |> Effect.Batch
                        |> (\cmd -> ( model |> popProcessedRequest, Effect.Batch [ cmd, sendManifestIfNeeded ] ))

                _ ->
                    ( model, Effect.SendJsData toJsPayload )


sendSinglePageProgress :
    ToJsSuccessPayload pathKey
    -> Config pathKey userMsg userModel route
    -> ContentCache
    -> Model pathKey route
    -> ( PagePath pathKey, route )
    -> Effect pathKey
sendSinglePageProgress toJsPayload config _ _ =
    \( page, _ ) ->
        let
            makeItWork : StaticHttpRequest.RawRequest staticData -> Result BuildError staticData
            makeItWork request =
                StaticHttpRequest.resolve ApplicationType.Browser request (staticData |> Dict.map (\_ v -> Just v))
                    |> Result.mapError (StaticHttpRequest.toBuildError (page |> PagePath.toString))

            staticData =
                toJsPayload.pages
                    |> Dict.get (PagePath.toString page)
                    |> Maybe.withDefault Dict.empty

            viewRequest :
                StaticHttp.Request
                    { view :
                        userModel
                        -> { title : String, body : Html userMsg }
                    , head : List (Head.Tag pathKey)
                    }
            viewRequest =
                config.view [] currentPage

            twoThings : Result BuildError { view : userModel -> { title : String, body : Html userMsg }, head : List (Head.Tag pathKey) }
            twoThings =
                viewRequest |> makeItWork

            currentPage : { path : PagePath pathKey, frontmatter : route }
            currentPage =
                { path = page, frontmatter = config.urlToRoute currentUrl }

            pageModel : userModel
            pageModel =
                config.init
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

            currentUrl =
                { protocol = Url.Https
                , host = config.canonicalSiteUrl
                , port_ = Nothing
                , path = page |> PagePath.toString
                , query = Nothing
                , fragment = Nothing
                }
        in
        case twoThings of
            Ok success ->
                let
                    viewValue =
                        success.view pageModel
                in
                { route = page |> PagePath.toString
                , contentJson =
                    toJsPayload.pages
                        |> Dict.get (PagePath.toString page)
                        |> Maybe.withDefault Dict.empty
                , html = viewValue.body |> viewRenderer
                , errors = []
                , head = success.head
                , title = viewValue.title
                , body = "" --lookedUp.unparsedBody
                }
                    |> sendProgress

            Err error ->
                error
                    |> BuildError.errorToString
                    |> ToJsPayload.Errors
                    |> Effect.SendJsData


popProcessedRequest model =
    { model | unprocessedPages = List.drop 1 model.unprocessedPages }


sendProgress : ToJsPayload.ToJsSuccessPayloadNew pathKey -> Effect pathKey
sendProgress singlePage =
    Effect.Batch
        [ singlePage |> ToJsPayload.PageProgress |> Effect.SendSinglePage

        --, Effect.Continue
        ]
