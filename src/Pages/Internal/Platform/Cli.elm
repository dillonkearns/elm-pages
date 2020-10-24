module Pages.Internal.Platform.Cli exposing
    ( Content
    , Flags
    , Model
    , Msg(..)
    , Page
    , cliApplication
    , init
    , update
    )

import BuildError exposing (BuildError)
import Codec exposing (Codec)
import Dict exposing (Dict)
import ElmHtml.InternalTypes exposing (decodeElmHtml)
import ElmHtml.ToString exposing (FormatOptions, defaultFormatOptions, nodeToStringWithOptions)
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.Http
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import Pages.Internal.Platform.StaticResponses as StaticResponses exposing (StaticResponses)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsPayload, ToJsSuccessPayload)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp exposing (RequestDetails)
import Pages.StaticHttpRequest as StaticHttpRequest
import SecretsDict exposing (SecretsDict)
import Task
import TerminalText as Terminal
import Url


type alias FileToGenerate =
    { path : List String
    , content : String
    }


type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias Flags =
    Decode.Value


type alias Model pathKey metadata =
    { staticResponses : StaticResponses
    , secrets : SecretsDict
    , errors : List BuildError
    , allRawResponses : Dict String (Maybe String)
    , mode : Mode
    , pendingRequests : List { masked : RequestDetails, unmasked : RequestDetails }
    , unprocessedPages : List ( PagePath pathKey, metadata )
    }


type Msg
    = GotStaticHttpResponse { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result Pages.Http.Error String }
    | Continue


type alias Config pathKey userMsg userModel metadata view =
    { init :
        Maybe
            { path :
                { path : PagePath pathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : metadata
            }
        -> ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : metadata -> PagePath pathKey -> userModel -> Sub userMsg
    , view :
        List ( PagePath pathKey, metadata )
        ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
        ->
            StaticHttp.Request
                { view : userModel -> view -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
    , document : Pages.Document.Document metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , manifest : Manifest.Config pathKey
    , generateFiles :
        List
            { path : PagePath pathKey
            , frontmatter : metadata
            , body : String
            }
        ->
            StaticHttp.Request
                (List
                    (Result String
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
             , metadata : metadata
             }
             -> userMsg
            )
    }


cliApplication :
    (Msg -> msg)
    -> (msg -> Maybe Msg)
    -> (Model pathKey metadata -> model)
    -> (model -> Maybe (Model pathKey metadata))
    -> Config pathKey userMsg userModel metadata view
    -> Platform.Program Flags model msg
cliApplication cliMsgConstructor narrowMsg toModel fromModel config =
    let
        contentCache =
            ContentCache.init config.document config.content Nothing

        siteMetadata =
            contentCache
                |> Result.map
                    (\cache -> cache |> ContentCache.extractMetadata config.pathKey)
                |> Result.mapError (List.map Tuple.second)
    in
    Platform.worker
        { init =
            \flags ->
                init toModel contentCache siteMetadata config flags
                    |> Tuple.mapSecond (perform config cliMsgConstructor config.toJsPort)
        , update =
            \msg model ->
                case ( narrowMsg msg, fromModel model ) of
                    ( Just cliMsg, Just cliModel ) ->
                        update contentCache siteMetadata config cliMsg cliModel
                            |> Tuple.mapSecond (perform config cliMsgConstructor config.toJsPort)
                            |> Tuple.mapFirst toModel

                    _ ->
                        ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


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


perform : Config pathKey userMsg userModel metadata view -> (Msg -> msg) -> (Json.Encode.Value -> Cmd Never) -> Effect pathKey -> Cmd msg
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


encodeFilesToGenerate list =
    list
        |> Json.Encode.list
            (\item ->
                Json.Encode.object
                    [ ( "path", item.path |> String.join "/" |> Json.Encode.string )
                    , ( "content", item.content |> Json.Encode.string )
                    ]
            )



--Task.succeed ()
--    |> Task.perform (\_ -> Continue)
--    |> Cmd.map cliMsgConstructor


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
    (Model pathKey metadata -> model)
    -> ContentCache.ContentCache metadata view
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Config pathKey userMsg userModel metadata view
    -> Decode.Value
    -> ( model, Effect pathKey )
init toModel contentCache siteMetadata config flags =
    case Decode.decodeValue flagsDecoder flags of
        Ok { secrets, mode, staticHttpCache } ->
            case mode of
                --Mode.ElmToHtmlBeta ->
                --    elmToHtmlBetaInit { secrets = secrets, mode = mode, staticHttpCache = staticHttpCache } toModel contentCache siteMetadata config flags
                --
                _ ->
                    initLegacy { secrets = secrets, mode = mode, staticHttpCache = staticHttpCache } toModel contentCache siteMetadata config flags

        Err error ->
            updateAndSendPortIfDone
                contentCache
                config
                siteMetadata
                (Model StaticResponses.error
                    SecretsDict.masked
                    [ { title = "Internal Error"
                      , message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ]
                      , fatal = True
                      }
                    ]
                    Dict.empty
                    Mode.Dev
                    []
                    (siteMetadata |> Result.withDefault [])
                )
                toModel


elmToHtmlBetaInit { secrets, mode, staticHttpCache } toModel contentCache siteMetadata config flags =
    --case flags of
    --init toModel contentCache siteMetadata config flags
    --|> Tuple.mapSecond (perform cliMsgConstructor config.toJsPort)
    --|> Tuple.mapSecond
    --    (\cmd ->
    --Cmd.map AppMsg
    --Cmd.none
    ( toModel
        (Model StaticResponses.error
            secrets
            []
            --(metadataParserErrors |> List.map Tuple.second)
            staticHttpCache
            mode
            []
        )
    , Effect.NoEffect
      --, { html =
      --        Html.div []
      --            [ Html.text "Hello!!!!!" ]
      --            |> viewRenderer
      --  }
      --    |> Effect.SendSinglePage
    )



--)


initLegacy { secrets, mode, staticHttpCache } toModel contentCache siteMetadata config flags =
    case contentCache of
        Ok _ ->
            case ContentCache.pagesWithErrors contentCache of
                [] ->
                    let
                        requests =
                            Result.andThen
                                (\metadata ->
                                    staticResponseForPage metadata config.view
                                )
                                siteMetadata

                        staticResponses : StaticResponses
                        staticResponses =
                            case requests of
                                Ok okRequests ->
                                    StaticResponses.init staticHttpCache siteMetadata config okRequests

                                Err errors ->
                                    -- TODO need to handle errors better?
                                    StaticResponses.init staticHttpCache siteMetadata config []
                    in
                    StaticResponses.nextStep config siteMetadata (siteMetadata |> Result.map (List.take 1)) mode secrets staticHttpCache [] staticResponses
                        |> nextStepToEffect contentCache config (Model staticResponses secrets [] staticHttpCache mode [] (siteMetadata |> Result.withDefault []))
                        |> Tuple.mapFirst toModel

                pageErrors ->
                    let
                        requests =
                            Result.andThen
                                (\metadata ->
                                    staticResponseForPage metadata config.view
                                )
                                siteMetadata

                        staticResponses : StaticResponses
                        staticResponses =
                            case requests of
                                Ok okRequests ->
                                    StaticResponses.init staticHttpCache siteMetadata config okRequests

                                Err errors ->
                                    -- TODO need to handle errors better?
                                    StaticResponses.init staticHttpCache siteMetadata config []
                    in
                    updateAndSendPortIfDone
                        contentCache
                        config
                        siteMetadata
                        (Model
                            staticResponses
                            secrets
                            pageErrors
                            staticHttpCache
                            mode
                            []
                            (siteMetadata |> Result.withDefault [])
                        )
                        toModel

        Err metadataParserErrors ->
            updateAndSendPortIfDone
                contentCache
                config
                siteMetadata
                (Model StaticResponses.error
                    secrets
                    (metadataParserErrors |> List.map Tuple.second)
                    staticHttpCache
                    mode
                    []
                    (siteMetadata |> Result.withDefault [])
                )
                toModel


updateAndSendPortIfDone :
    ContentCache.ContentCache metadata view
    -> Config pathKey userMsg userModel metadata view
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Model pathKey metadata
    -> (Model pathKey metadata -> model)
    -> ( model, Effect pathKey )
updateAndSendPortIfDone contentCache config siteMetadata model toModel =
    let
        nextToProcess =
            drop1 model
    in
    StaticResponses.nextStep
        config
        siteMetadata
        (Ok nextToProcess)
        model.mode
        model.secrets
        model.allRawResponses
        model.errors
        model.staticResponses
        |> nextStepToEffect contentCache config model
        |> Tuple.mapFirst toModel


drop1 model =
    List.take 1 model.unprocessedPages



--, { model | unprocessedPages = List.drop 1 model.unprocessedPages }


update :
    ContentCache.ContentCache metadata view
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Config pathKey userMsg userModel metadata view
    -> Msg
    -> Model pathKey metadata
    -> ( Model pathKey metadata, Effect pathKey )
update contentCache siteMetadata config msg model =
    case msg of
        GotStaticHttpResponse { request, response } ->
            let
                -- _ =
                --     Debug.log "Got response" request.masked.url
                --
                updatedModel =
                    (case response of
                        Ok okResponse ->
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

                nextToProcess =
                    drop1 updatedModel
            in
            StaticResponses.nextStep config
                siteMetadata
                (Ok nextToProcess)
                updatedModel.mode
                updatedModel.secrets
                updatedModel.allRawResponses
                updatedModel.errors
                updatedModel.staticResponses
                |> nextStepToEffect contentCache config updatedModel

        Continue ->
            -- TODO
            let
                --_ =
                --    Debug.log "Continuing..." (List.length model.unprocessedPages)
                updatedModel =
                    model

                --|> popProcessedRequest
                nextToProcess =
                    drop1 model
            in
            StaticResponses.nextStep config
                siteMetadata
                (Ok nextToProcess)
                updatedModel.mode
                updatedModel.secrets
                updatedModel.allRawResponses
                updatedModel.errors
                updatedModel.staticResponses
                |> nextStepToEffect contentCache config updatedModel


nextStepToEffect :
    ContentCache.ContentCache metadata view
    -> Config pathKey userMsg userModel metadata view
    -> Model pathKey metadata
    -> StaticResponses.NextStep pathKey
    -> ( Model pathKey metadata, Effect pathKey )
nextStepToEffect contentCache config model nextStep =
    case nextStep of
        StaticResponses.Continue updatedAllRawResponses httpRequests ->
            let
                nextAndPending =
                    model.pendingRequests ++ httpRequests

                doNow =
                    nextAndPending

                pending =
                    []
            in
            ( { model
                | allRawResponses = updatedAllRawResponses
                , pendingRequests = pending
              }
            , doNow
                |> List.map Effect.FetchHttp
                |> Effect.Batch
            )

        StaticResponses.Finish toJsPayload ->
            case model.mode of
                Mode.ElmToHtmlBeta ->
                    let
                        siteMetadata =
                            contentCache
                                --|> Debug.log "contentCache"
                                |> Result.map
                                    (\cache -> cache |> ContentCache.extractMetadata config.pathKey)
                                |> Result.mapError (List.map Tuple.second)

                        --viewFnResult =
                        --    --currentPage
                        --         config.view siteMetadata currentPage
                        --            --(contentCache
                        --            --    |> Result.map (ContentCache.extractMetadata pathKey)
                        --            --    |> Result.withDefault []
                        --            -- -- TODO handle error better
                        --            --)
                        --        |> (\request ->
                        --                StaticHttpRequest.resolve ApplicationType.Browser request viewResult.staticData
                        --           )
                        --makeItWork :
                        --    StaticHttp.Request
                        --        { view :
                        --            userModel
                        --            -> view
                        --            -> { title : String, body : Html userMsg }
                        --        , head : List (Head.Tag pathKey)
                        --        }
                        --    -> { title : String, body : Html userMsg }
                    in
                    case siteMetadata of
                        Ok pages ->
                            let
                                sendManifestIfNeeded =
                                    if List.length model.unprocessedPages == List.length pages then
                                        case toJsPayload of
                                            ToJsPayload.Success value ->
                                                Effect.SendSinglePage
                                                    (ToJsPayload.InitialData
                                                        { manifest = value.manifest
                                                        , filesToGenerate = value.filesToGenerate
                                                        }
                                                    )

                                            ToJsPayload.Errors errorMessage ->
                                                Effect.SendJsData toJsPayload

                                    else
                                        Effect.NoEffect
                            in
                            model.unprocessedPages
                                |> List.take 1
                                --|> Debug.log "@@@ pages"
                                |> List.filterMap
                                    (\pageAndMetadata ->
                                        case toJsPayload of
                                            ToJsPayload.Success value ->
                                                sendSinglePageProgress value siteMetadata config contentCache model pageAndMetadata
                                                    |> Just

                                            ToJsPayload.Errors errorMessage ->
                                                Nothing
                                    )
                                |> Effect.Batch
                                |> (\cmd -> ( model |> popProcessedRequest, Effect.Batch [ cmd, sendManifestIfNeeded ] ))

                        Err error ->
                            ( model
                            , Effect.SendJsData
                                (ToJsPayload.Errors <|
                                    BuildError.errorsToString error
                                )
                            )

                _ ->
                    ( model, Effect.SendJsData toJsPayload )


sendSinglePageProgress :
    ToJsSuccessPayload pathKey
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Config pathKey userMsg userModel metadata view
    -> ContentCache metadata view
    -> Model pathKey metadata
    -> ( PagePath pathKey, metadata )
    -> Effect pathKey
sendSinglePageProgress toJsPayload siteMetadata config contentCache model =
    \( page, metadata ) ->
        let
            makeItWork : StaticHttpRequest.Request staticData -> Result BuildError staticData
            makeItWork request =
                StaticHttpRequest.resolve ApplicationType.Browser request (staticData |> Dict.map (\k v -> Just v))
                    |> Result.mapError (StaticHttpRequest.toBuildError (page |> PagePath.toString))

            staticData =
                toJsPayload.pages
                    |> Dict.get (PagePath.toString page)
                    |> Maybe.withDefault Dict.empty

            viewRequest :
                StaticHttp.Request
                    { view :
                        userModel
                        -> view
                        -> { title : String, body : Html userMsg }
                    , head : List (Head.Tag pathKey)
                    }
            viewRequest =
                config.view (siteMetadata |> Result.withDefault []) currentPage

            twoThings : Result BuildError { view : userModel -> view -> { title : String, body : Html userMsg }, head : List (Head.Tag pathKey) }
            twoThings =
                viewRequest |> makeItWork

            renderer value =
                ContentCache.parseContent "md" value config.document

            updatedCache =
                ContentCache.update contentCache
                    renderer
                    urls
                    { body = "", staticData = model.allRawResponses }

            currentPage : { path : PagePath pathKey, frontmatter : metadata }
            currentPage =
                { path = page, frontmatter = metadata }

            pageModel : userModel
            pageModel =
                config.init
                    (Just
                        { path =
                            { path = currentPage.path
                            , query = Nothing
                            , fragment = Nothing
                            }
                        , metadata = metadata
                        }
                    )
                    |> Tuple.first

            currentUrl =
                { protocol = Url.Https
                , host = config.canonicalSiteUrl
                , port_ = Nothing
                , path = currentPage.path |> PagePath.toString
                , query = Nothing
                , fragment = Nothing
                }

            urls =
                { currentUrl = currentUrl
                , baseUrl =
                    { protocol = Url.Https
                    , host = config.canonicalSiteUrl
                    , port_ = Nothing
                    , path = ""
                    , query = Nothing
                    , fragment = Nothing
                    }
                }

            value2 =
                case ContentCache.lookup config.pathKey updatedCache urls of
                    Just ( path, ContentCache.Parsed frontmatter unparsedBody viewResult ) ->
                        viewResult.body
                            |> Result.map
                                (\body ->
                                    { body = body
                                    , viewResult = viewResult
                                    , unparsedBody = unparsedBody
                                    }
                                )
                            |> Result.mapError
                                (\parseError ->
                                    { title = "Internal Error"
                                    , message = [ Terminal.text parseError ]
                                    , fatal = True
                                    }
                                )

                    _ ->
                        Err
                            { title = "Internal Error"
                            , message = [ Terminal.text "Unable to lookup value in ContentCache." ]
                            , fatal = True
                            }
        in
        case Result.map2 Tuple.pair twoThings value2 of
            Ok ( success, lookedUp ) ->
                let
                    viewValue =
                        success.view pageModel lookedUp.body
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
                , body = lookedUp.unparsedBody
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


staticResponseForPage :
    List ( PagePath pathKey, metadata )
    ->
        (List ( PagePath pathKey, metadata )
         ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
         ->
            StaticHttpRequest.Request
                { view : userModel -> view -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
        )
    ->
        Result (List BuildError)
            (List
                ( PagePath pathKey
                , StaticHttp.Request
                    { view : userModel -> view -> { title : String, body : Html userMsg }
                    , head : List (Head.Tag pathKey)
                    }
                )
            )
staticResponseForPage siteMetadata viewFn =
    siteMetadata
        |> List.map
            (\( pagePath, frontmatter ) ->
                let
                    thing =
                        viewFn siteMetadata
                            { path = pagePath
                            , frontmatter = frontmatter
                            }
                in
                Ok ( pagePath, thing )
            )
        |> combine


combine : List (Result error ( key, success )) -> Result (List error) (List ( key, success ))
combine list =
    list
        |> List.foldr resultFolder (Ok [])


resultFolder : Result error a -> Result (List error) (List a) -> Result (List error) (List a)
resultFolder current soFarResult =
    case soFarResult of
        Ok soFarOk ->
            case current of
                Ok currentOk ->
                    currentOk
                        :: soFarOk
                        |> Ok

                Err error ->
                    Err [ error ]

        Err soFarErr ->
            case current of
                Ok currentOk ->
                    Err soFarErr

                Err error ->
                    error
                        :: soFarErr
                        |> Err
