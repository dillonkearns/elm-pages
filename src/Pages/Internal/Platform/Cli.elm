module Pages.Internal.Platform.Cli exposing (Flags, Model, Msg(..), Program, cliApplication, init, requestDecoder, update, currentCompatibilityKey)

{-| Exposed for internal use only (used in generated code).

@docs Flags, Model, Msg, Program, cliApplication, init, requestDecoder, update, currentCompatibilityKey

-}

import BackendTask exposing (BackendTask)
import BuildError exposing (BuildError)
import Bytes exposing (Bytes)
import Bytes.Encode
import Codec
import Dict exposing (Dict)
import FatalError exposing (FatalError)
import Head exposing (Tag)
import Html exposing (Html)
import HtmlPrinter
import Internal.ApiRoute exposing (ApiRoute(..))
import Json.Decode as Decode
import Json.Encode
import PageServerResponse exposing (PageServerResponse)
import Pages.Flags
import Pages.Internal.FatalError
import Pages.Internal.NotFoundReason as NotFoundReason exposing (NotFoundReason)
import Pages.Internal.Platform.CompatibilityKey
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.StaticResponses as StaticResponses
import Pages.Internal.Platform.ToJsPayload as ToJsPayload
import Pages.Internal.ResponseSketch as ResponseSketch
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.SiteConfig exposing (SiteConfig)
import Pages.StaticHttp.Request
import PagesMsg exposing (PagesMsg)
import RenderRequest exposing (RenderRequest)
import RequestsAndPending exposing (RequestsAndPending)
import TerminalText as Terminal
import Url exposing (Url)
import UrlPath exposing (UrlPath)


{-| -}
type alias Flags =
    Decode.Value


{-| -}
currentCompatibilityKey : Int
currentCompatibilityKey =
    Pages.Internal.Platform.CompatibilityKey.currentCompatibilityKey


{-| -}
type alias Model route =
    { staticResponses : BackendTask FatalError Effect
    , errors : List BuildError
    , maybeRequestJson : RenderRequest route
    , isDevServer : Bool
    }


{-| -}
type Msg
    = GotDataBatch Decode.Value
    | GotBuildError BuildError


{-| -}
type alias Program route =
    Platform.Program Flags (Model route) Msg


{-| -}
cliApplication :
    ProgramConfig userMsg userModel (Maybe route) pageData actionData sharedData effect mappedMsg errorPage
    -> Program (Maybe route)
cliApplication config =
    let
        site : SiteConfig
        site =
            getSiteConfig config

        getSiteConfig : ProgramConfig userMsg userModel (Maybe route) pageData actionData sharedData effect mappedMsg errorPage -> SiteConfig
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
                update msg model
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
                                    |> Result.mapError
                                        (\error ->
                                            ("From location 1: "
                                                ++ (error
                                                        |> Decode.errorToString
                                                   )
                                            )
                                                |> BuildError.internal
                                                |> GotBuildError
                                        )
                                    |> mergeResult
                            )
                    , config.gotBatchSub |> Sub.map GotDataBatch
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


flatten : SiteConfig -> RenderRequest route -> ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage -> List Effect -> Cmd Msg
flatten site renderRequest config list =
    Cmd.batch (flattenHelp [] site renderRequest config list)


flattenHelp : List (Cmd Msg) -> SiteConfig -> RenderRequest route -> ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage -> List Effect -> List (Cmd Msg)
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
    -> ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage
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

        Effect.FetchHttp requests ->
            requests
                |> List.map
                    (\request ->
                        ( Pages.StaticHttp.Request.hash request, request )
                    )
                |> ToJsPayload.DoHttp
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


flagsDecoder :
    Decode.Decoder
        { staticHttpCache : RequestsAndPending
        , isDevServer : Bool
        , compatibilityKey : Int
        }
flagsDecoder =
    Decode.map3
        (\staticHttpCache isDevServer compatibilityKey ->
            { staticHttpCache = staticHttpCache
            , isDevServer = isDevServer
            , compatibilityKey = compatibilityKey
            }
        )
        -- TODO remove hardcoding and decode staticHttpCache here
        (Decode.succeed (Json.Encode.object []))
        (Decode.field "mode" Decode.string |> Decode.map (\mode -> mode == "dev-server"))
        (Decode.field "compatibilityKey" Decode.int)


{-| -}
init :
    SiteConfig
    -> RenderRequest route
    -> ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage
    -> Decode.Value
    -> ( Model route, Effect )
init site renderRequest config flags =
    case Decode.decodeValue flagsDecoder flags of
        Ok { isDevServer, compatibilityKey } ->
            if compatibilityKey == currentCompatibilityKey then
                initLegacy site renderRequest { isDevServer = isDevServer } config

            else
                let
                    elmPackageAheadOfNpmPackage : Bool
                    elmPackageAheadOfNpmPackage =
                        currentCompatibilityKey > compatibilityKey

                    message : String
                    message =
                        "The NPM package and Elm package you have installed are incompatible. If you are updating versions, be sure to update both the elm-pages Elm and NPM package.\n\n"
                            ++ (if elmPackageAheadOfNpmPackage then
                                    "The elm-pages Elm package is ahead of the elm-pages NPM package. Try updating the elm-pages NPM package?"

                                else
                                    "The elm-pages NPM package is ahead of the elm-pages Elm package. Try updating the elm-pages Elm package?"
                               )
                in
                updateAndSendPortIfDone
                    { staticResponses = StaticResponses.empty Effect.NoEffect
                    , errors =
                        [ { title = "Incompatible NPM and Elm package versions"
                          , message = [ Terminal.text <| message ]
                          , fatal = True
                          , path = ""
                          }
                        ]
                    , maybeRequestJson = renderRequest
                    , isDevServer = False
                    }

        Err error ->
            updateAndSendPortIfDone
                { staticResponses = StaticResponses.empty Effect.NoEffect
                , errors =
                    [ { title = "Internal Error"
                      , message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ]
                      , fatal = True
                      , path = ""
                      }
                    ]
                , maybeRequestJson = renderRequest
                , isDevServer = False
                }


type ActionRequest
    = ActionResponseRequest
    | ActionOnlyRequest


isActionDecoder : Decode.Decoder (Maybe ActionRequest)
isActionDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "method" Decode.string)
        (Decode.field "headers" (Decode.dict Decode.string))
        |> Decode.map
            (\( method, headers ) ->
                case method |> String.toUpper of
                    "GET" ->
                        Nothing

                    "OPTIONS" ->
                        Nothing

                    _ ->
                        let
                            actionOnly : Bool
                            actionOnly =
                                case headers |> Dict.get "elm-pages-action-only" of
                                    Just _ ->
                                        True

                                    Nothing ->
                                        False
                        in
                        Just
                            (if actionOnly then
                                ActionOnlyRequest

                             else
                                ActionResponseRequest
                            )
            )


initLegacy :
    SiteConfig
    -> RenderRequest route
    -> { isDevServer : Bool }
    -> ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage
    -> ( Model route, Effect )
initLegacy site ((RenderRequest.SinglePage includeHtml singleRequest _) as renderRequest) { isDevServer } config =
    let
        globalHeadTags : BackendTask FatalError (List Tag)
        globalHeadTags =
            (config.globalHeadTags |> Maybe.withDefault (\_ -> BackendTask.succeed [])) HtmlPrinter.htmlToString

        staticResponsesNew : BackendTask FatalError Effect
        staticResponsesNew =
            case singleRequest of
                RenderRequest.Page serverRequestPayload ->
                    let
                        isAction : Maybe ActionRequest
                        isAction =
                            renderRequest
                                |> RenderRequest.maybeRequestPayload
                                |> Maybe.andThen (Decode.decodeValue isActionDecoder >> Result.withDefault Nothing)

                        currentUrl : Url
                        currentUrl =
                            { protocol = Url.Https
                            , host = site.canonicalUrl
                            , port_ = Nothing
                            , path = serverRequestPayload.path |> UrlPath.toRelative
                            , query = Nothing
                            , fragment = Nothing
                            }
                    in
                    --case isAction of
                    --    Just actionRequest ->
                    (if isDevServer then
                        config.handleRoute serverRequestPayload.frontmatter

                     else
                        BackendTask.succeed Nothing
                    )
                        |> BackendTask.andThen
                            (\pageFound ->
                                case pageFound of
                                    Nothing ->
                                        --sendSinglePageProgress site model.allRawResponses config model payload
                                        (case isAction of
                                            Just _ ->
                                                config.action (RenderRequest.maybeRequestPayload renderRequest |> Maybe.withDefault Json.Encode.null) serverRequestPayload.frontmatter |> BackendTask.map Just

                                            Nothing ->
                                                BackendTask.succeed Nothing
                                        )
                                            |> BackendTask.andThen
                                                (\something ->
                                                    let
                                                        actionHeaders2 : Maybe { statusCode : Int, headers : List ( String, String ) }
                                                        actionHeaders2 =
                                                            case something of
                                                                Just (PageServerResponse.RenderPage responseThing _) ->
                                                                    Just responseThing

                                                                Just (PageServerResponse.ServerResponse responseThing) ->
                                                                    Just
                                                                        { headers = responseThing.headers
                                                                        , statusCode = responseThing.statusCode
                                                                        }

                                                                _ ->
                                                                    Nothing

                                                        maybeRedirectResponse : Maybe Effect
                                                        maybeRedirectResponse =
                                                            actionHeaders2
                                                                |> Maybe.andThen
                                                                    (\responseMetadata ->
                                                                        toRedirectResponse config
                                                                            serverRequestPayload
                                                                            includeHtml
                                                                            responseMetadata
                                                                            responseMetadata
                                                                    )
                                                    in
                                                    case maybeRedirectResponse of
                                                        Just redirectResponse ->
                                                            redirectResponse
                                                                |> BackendTask.succeed

                                                        Nothing ->
                                                            BackendTask.map3
                                                                (\pageData sharedData tags ->
                                                                    let
                                                                        renderedResult : Effect
                                                                        renderedResult =
                                                                            case pageData of
                                                                                PageServerResponse.RenderPage responseInfo pageData_ ->
                                                                                    let
                                                                                        currentPage : { path : UrlPath, route : route }
                                                                                        currentPage =
                                                                                            { path = serverRequestPayload.path, route = urlToRoute config currentUrl }

                                                                                        maybeActionData : Maybe actionData
                                                                                        maybeActionData =
                                                                                            case something of
                                                                                                Just (PageServerResponse.RenderPage _ actionThing) ->
                                                                                                    Just actionThing

                                                                                                _ ->
                                                                                                    Nothing

                                                                                        pageModel : userModel
                                                                                        pageModel =
                                                                                            config.init
                                                                                                Pages.Flags.PreRenderFlags
                                                                                                sharedData
                                                                                                pageData_
                                                                                                maybeActionData
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

                                                                                        viewValue : { title : String, body : List (Html (PagesMsg userMsg)) }
                                                                                        viewValue =
                                                                                            (config.view Dict.empty Dict.empty Nothing currentPage Nothing sharedData pageData_ maybeActionData |> .view) pageModel

                                                                                        responseMetadata : { statusCode : Int, headers : List ( String, String ) }
                                                                                        responseMetadata =
                                                                                            actionHeaders2 |> Maybe.withDefault responseInfo
                                                                                    in
                                                                                    (case isAction of
                                                                                        Just actionRequestKind ->
                                                                                            let
                                                                                                actionDataResult : Maybe (PageServerResponse actionData errorPage)
                                                                                                actionDataResult =
                                                                                                    something
                                                                                            in
                                                                                            case actionDataResult of
                                                                                                Just (PageServerResponse.RenderPage ignored2 actionData_) ->
                                                                                                    case actionRequestKind of
                                                                                                        ActionResponseRequest ->
                                                                                                            ( ignored2.headers
                                                                                                            , ResponseSketch.HotUpdate pageData_ sharedData (Just actionData_)
                                                                                                                |> config.encodeResponse
                                                                                                                |> Bytes.Encode.encode
                                                                                                            )

                                                                                                        ActionOnlyRequest ->
                                                                                                            ---- TODO need to encode action data when only that is requested (not ResponseSketch?)
                                                                                                            ( ignored2.headers
                                                                                                            , actionData_
                                                                                                                |> config.encodeAction
                                                                                                                |> Bytes.Encode.encode
                                                                                                            )

                                                                                                _ ->
                                                                                                    ( responseMetadata.headers
                                                                                                    , Bytes.Encode.encode (Bytes.Encode.unsignedInt8 0)
                                                                                                    )

                                                                                        Nothing ->
                                                                                            ( responseMetadata.headers
                                                                                            , ResponseSketch.HotUpdate pageData_ sharedData Nothing
                                                                                                |> config.encodeResponse
                                                                                                |> Bytes.Encode.encode
                                                                                            )
                                                                                    )
                                                                                        |> (\( actionHeaders, byteEncodedPageData ) ->
                                                                                                let
                                                                                                    rendered : { view : userModel -> { title : String, body : List (Html (PagesMsg userMsg)) }, head : List Tag }
                                                                                                    rendered =
                                                                                                        config.view Dict.empty Dict.empty Nothing currentPage Nothing sharedData pageData_ maybeActionData
                                                                                                in
                                                                                                PageServerResponse.toRedirect responseMetadata
                                                                                                    |> Maybe.map
                                                                                                        (\{ location } ->
                                                                                                            location
                                                                                                                |> ResponseSketch.Redirect
                                                                                                                |> config.encodeResponse
                                                                                                                |> Bytes.Encode.encode
                                                                                                        )
                                                                                                    -- TODO handle other cases besides redirects?
                                                                                                    |> Maybe.withDefault byteEncodedPageData
                                                                                                    |> (\encodedData ->
                                                                                                            { route = currentPage.path |> UrlPath.toRelative
                                                                                                            , contentJson = Dict.empty
                                                                                                            , html = viewValue.body |> bodyToString
                                                                                                            , errors = []
                                                                                                            , head = rendered.head ++ tags
                                                                                                            , title = viewValue.title
                                                                                                            , staticHttpCache = Dict.empty
                                                                                                            , is404 = False
                                                                                                            , statusCode =
                                                                                                                case includeHtml of
                                                                                                                    RenderRequest.OnlyJson ->
                                                                                                                        200

                                                                                                                    RenderRequest.HtmlAndJson ->
                                                                                                                        responseMetadata.statusCode
                                                                                                            , headers =
                                                                                                                -- TODO should `responseInfo.headers` be used? Is there a problem in the case where there is both an action and data response in one? Do we need to make sure it is performed as two separate HTTP requests to ensure that the cookies are set correctly in that case?
                                                                                                                actionHeaders
                                                                                                                    |> combineHeaders
                                                                                                            }
                                                                                                                |> ToJsPayload.PageProgress
                                                                                                                |> Effect.SendSinglePageNew encodedData
                                                                                                       )
                                                                                           )

                                                                                PageServerResponse.ServerResponse serverResponse ->
                                                                                    --PageServerResponse.ServerResponse serverResponse
                                                                                    -- TODO handle error?
                                                                                    let
                                                                                        responseMetadata : PageServerResponse.Response
                                                                                        responseMetadata =
                                                                                            case something of
                                                                                                Just (PageServerResponse.ServerResponse responseThing) ->
                                                                                                    responseThing

                                                                                                _ ->
                                                                                                    serverResponse
                                                                                    in
                                                                                    toRedirectResponse config serverRequestPayload includeHtml serverResponse responseMetadata
                                                                                        |> Maybe.withDefault
                                                                                            ({ body = serverResponse |> PageServerResponse.toJson
                                                                                             , staticHttpCache = Dict.empty
                                                                                             , statusCode = serverResponse.statusCode
                                                                                             }
                                                                                                |> ToJsPayload.SendApiResponse
                                                                                                |> Effect.SendSinglePage
                                                                                            )

                                                                                PageServerResponse.ErrorPage error record ->
                                                                                    let
                                                                                        currentPage : { path : UrlPath, route : route }
                                                                                        currentPage =
                                                                                            { path = serverRequestPayload.path, route = urlToRoute config currentUrl }

                                                                                        pageModel : userModel
                                                                                        pageModel =
                                                                                            config.init
                                                                                                Pages.Flags.PreRenderFlags
                                                                                                sharedData
                                                                                                pageData2
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

                                                                                        pageData2 : pageData
                                                                                        pageData2 =
                                                                                            config.errorPageToData error

                                                                                        viewValue : { title : String, body : List (Html (PagesMsg userMsg)) }
                                                                                        viewValue =
                                                                                            (config.view Dict.empty Dict.empty Nothing currentPage Nothing sharedData pageData2 Nothing |> .view) pageModel
                                                                                    in
                                                                                    (ResponseSketch.HotUpdate pageData2 sharedData Nothing
                                                                                        |> config.encodeResponse
                                                                                        |> Bytes.Encode.encode
                                                                                    )
                                                                                        |> (\encodedData ->
                                                                                                { route = currentPage.path |> UrlPath.toRelative
                                                                                                , contentJson = Dict.empty
                                                                                                , html = viewValue.body |> bodyToString
                                                                                                , errors = []
                                                                                                , head = tags
                                                                                                , title = viewValue.title
                                                                                                , staticHttpCache = Dict.empty
                                                                                                , is404 = False
                                                                                                , statusCode =
                                                                                                    case includeHtml of
                                                                                                        RenderRequest.OnlyJson ->
                                                                                                            200

                                                                                                        RenderRequest.HtmlAndJson ->
                                                                                                            config.errorStatusCode error
                                                                                                , headers = record.headers |> combineHeaders
                                                                                                }
                                                                                                    |> ToJsPayload.PageProgress
                                                                                                    |> Effect.SendSinglePageNew encodedData
                                                                                           )
                                                                    in
                                                                    renderedResult
                                                                )
                                                                (config.data (RenderRequest.maybeRequestPayload renderRequest |> Maybe.withDefault Json.Encode.null) serverRequestPayload.frontmatter)
                                                                config.sharedData
                                                                globalHeadTags
                                                )
                                            |> BackendTask.onError
                                                (\((Pages.Internal.FatalError.FatalError fatalError) as error) ->
                                                    let
                                                        isPreRendered : Bool
                                                        isPreRendered =
                                                            let
                                                                keys : Int
                                                                keys =
                                                                    RenderRequest.maybeRequestPayload renderRequest |> Maybe.map (Decode.decodeValue (Decode.keyValuePairs Decode.value)) |> Maybe.withDefault (Ok []) |> Result.withDefault [] |> List.map Tuple.first |> List.length
                                                            in
                                                            -- TODO this is a bit hacky, would be nice to clean up the way of checking whether this is server-rendered or pre-rendered
                                                            keys <= 1
                                                    in
                                                    if isDevServer || isPreRendered then
                                                        -- we want to stop the build for pre-rendered routes, and give a dev server error popup in the dev server
                                                        BackendTask.fail error

                                                    else
                                                        --only render the production ErrorPage in production server-rendered Routes
                                                        config.sharedData
                                                            |> BackendTask.andThen
                                                                (\justSharedData ->
                                                                    let
                                                                        errorPage : errorPage
                                                                        errorPage =
                                                                            config.internalError fatalError.body

                                                                        dataThing : pageData
                                                                        dataThing =
                                                                            errorPage
                                                                                |> config.errorPageToData

                                                                        statusCode : Int
                                                                        statusCode =
                                                                            config.errorStatusCode errorPage

                                                                        byteEncodedPageData : Bytes
                                                                        byteEncodedPageData =
                                                                            ResponseSketch.HotUpdate
                                                                                dataThing
                                                                                justSharedData
                                                                                -- TODO remove shared action data
                                                                                Nothing
                                                                                |> config.encodeResponse
                                                                                |> Bytes.Encode.encode

                                                                        pageModel : userModel
                                                                        pageModel =
                                                                            config.init
                                                                                Pages.Flags.PreRenderFlags
                                                                                justSharedData
                                                                                dataThing
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

                                                                        currentPage : { path : UrlPath, route : route }
                                                                        currentPage =
                                                                            { path = serverRequestPayload.path, route = urlToRoute config currentUrl }

                                                                        viewValue : { title : String, body : List (Html (PagesMsg userMsg)) }
                                                                        viewValue =
                                                                            (config.view Dict.empty Dict.empty Nothing currentPage Nothing justSharedData dataThing Nothing |> .view)
                                                                                pageModel
                                                                    in
                                                                    { route = UrlPath.toAbsolute currentPage.path
                                                                    , contentJson = Dict.empty
                                                                    , html = viewValue.body |> bodyToString
                                                                    , errors = []
                                                                    , head = [] -- TODO render head tags --config.view Dict.empty Dict.empty Nothing pathAndRoute Nothing justSharedData pageData Nothing |> .head
                                                                    , title = viewValue.title
                                                                    , staticHttpCache = Dict.empty
                                                                    , is404 = False
                                                                    , statusCode = statusCode
                                                                    , headers = Dict.empty
                                                                    }
                                                                        |> ToJsPayload.PageProgress
                                                                        |> Effect.SendSinglePageNew byteEncodedPageData
                                                                        |> BackendTask.succeed
                                                                )
                                                )

                                    Just notFoundReason ->
                                        render404Page config
                                            Nothing
                                            -- TODO do I need sharedDataResult?
                                            --(Result.toMaybe sharedDataResult)
                                            isDevServer
                                            serverRequestPayload.path
                                            notFoundReason
                                            |> BackendTask.succeed
                            )

                RenderRequest.Api ( path, ApiRoute apiHandler ) ->
                    BackendTask.map2
                        (\response _ ->
                            case response of
                                Just okResponse ->
                                    { body = okResponse
                                    , staticHttpCache = Dict.empty -- TODO do I need to serialize the full cache here, or can I handle that from the JS side?
                                    , statusCode = 200
                                    }
                                        |> ToJsPayload.SendApiResponse
                                        |> Effect.SendSinglePage

                                Nothing ->
                                    render404Page config
                                        -- TODO do I need sharedDataResult here?
                                        Nothing
                                        isDevServer
                                        (UrlPath.fromString path)
                                        NotFoundReason.NoMatchingRoute
                         --Err error ->
                         --    [ error ]
                         --        |> ToJsPayload.Errors
                         --        |> Effect.SendSinglePage
                        )
                        (apiHandler.matchesToResponse
                            (renderRequest
                                |> RenderRequest.maybeRequestPayload
                                |> Maybe.withDefault Json.Encode.null
                            )
                            path
                        )
                        globalHeadTags

                RenderRequest.NotFound notFoundPath ->
                    (BackendTask.map2
                        (\_ _ ->
                            render404Page config
                                Nothing
                                --(Result.toMaybe sharedDataResult)
                                --model
                                isDevServer
                                notFoundPath
                                NotFoundReason.NoMatchingRoute
                        )
                        (BackendTask.succeed [])
                        globalHeadTags
                     -- TODO is there a way to resolve sharedData but get it as a Result if it fails?
                     --config.sharedData
                    )

        initialModel : Model route
        initialModel =
            { staticResponses = staticResponsesNew
            , errors = []
            , maybeRequestJson = renderRequest
            , isDevServer = isDevServer
            }
    in
    StaticResponses.nextStep (Json.Encode.object []) initialModel.staticResponses initialModel
        |> nextStepToEffect
            initialModel


updateAndSendPortIfDone :
    Model route
    -> ( Model route, Effect )
updateAndSendPortIfDone model =
    StaticResponses.nextStep (Json.Encode.object [])
        model.staticResponses
        model
        |> nextStepToEffect model


{-| -}
update :
    Msg
    -> Model route
    -> ( Model route, Effect )
update msg model =
    case msg of
        GotDataBatch batch ->
            StaticResponses.nextStep batch
                model.staticResponses
                model
                |> nextStepToEffect model

        GotBuildError buildError ->
            let
                updatedModel : Model route
                updatedModel =
                    { model
                        | errors =
                            buildError :: model.errors
                    }
            in
            StaticResponses.nextStep (Json.Encode.object [])
                updatedModel.staticResponses
                updatedModel
                |> nextStepToEffect updatedModel


nextStepToEffect :
    Model route
    -> StaticResponses.NextStep route Effect
    -> ( Model route, Effect )
nextStepToEffect model nextStep =
    case nextStep of
        StaticResponses.Continue httpRequests updatedStaticResponsesModel ->
            ( { model
                | staticResponses = updatedStaticResponsesModel
              }
            , Effect.FetchHttp httpRequests
            )

        StaticResponses.FinishedWithErrors errors ->
            ( model
            , errors |> ToJsPayload.Errors |> Effect.SendSinglePage
            )

        StaticResponses.Finish finalValue ->
            ( model
            , finalValue
            )


render404Page :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage
    -> Maybe sharedData
    -> Bool
    -> UrlPath
    -> NotFoundReason
    -> Effect
render404Page config sharedData isDevServer path notFoundReason =
    case ( isDevServer, sharedData ) of
        ( False, Just justSharedData ) ->
            let
                byteEncodedPageData : Bytes
                byteEncodedPageData =
                    ResponseSketch.HotUpdate
                        (config.errorPageToData config.notFoundPage)
                        justSharedData
                        -- TODO remove shared action data
                        Nothing
                        |> config.encodeResponse
                        |> Bytes.Encode.encode

                pageModel : userModel
                pageModel =
                    config.init
                        Pages.Flags.PreRenderFlags
                        justSharedData
                        pageData
                        Nothing
                        Nothing
                        |> Tuple.first

                pageData : pageData
                pageData =
                    config.errorPageToData config.notFoundPage

                pathAndRoute : { path : UrlPath, route : route }
                pathAndRoute =
                    { path = path, route = config.notFoundRoute }

                viewValue : { title : String, body : List (Html (PagesMsg userMsg)) }
                viewValue =
                    (config.view Dict.empty
                        Dict.empty
                        Nothing
                        pathAndRoute
                        Nothing
                        justSharedData
                        pageData
                        Nothing
                        |> .view
                    )
                        pageModel
            in
            { route = UrlPath.toAbsolute path
            , contentJson = Dict.empty
            , html = viewValue.body |> bodyToString
            , errors = []
            , head = config.view Dict.empty Dict.empty Nothing pathAndRoute Nothing justSharedData pageData Nothing |> .head
            , title = viewValue.title
            , staticHttpCache = Dict.empty
            , is404 = True
            , statusCode = 404
            , headers = Dict.empty
            }
                |> ToJsPayload.PageProgress
                |> Effect.SendSinglePageNew byteEncodedPageData

        _ ->
            let
                byteEncodedPageData : Bytes
                byteEncodedPageData =
                    ResponseSketch.NotFound { reason = notFoundReason, path = path }
                        |> config.encodeResponse
                        |> Bytes.Encode.encode

                notFoundDocument : { title : String, body : List (Html msg) }
                notFoundDocument =
                    { path = path
                    , reason = notFoundReason
                    }
                        |> NotFoundReason.document config.pathPatterns
            in
            { route = UrlPath.toAbsolute path
            , contentJson = Dict.empty
            , html = bodyToString notFoundDocument.body
            , errors = []
            , head = []
            , title = notFoundDocument.title
            , staticHttpCache = Dict.empty

            -- TODO can I handle caching from the JS-side only?
            --model.allRawResponses |> Dict.Extra.filterMap (\_ v -> v)
            , is404 = True
            , statusCode = 404
            , headers = Dict.empty
            }
                |> ToJsPayload.PageProgress
                |> Effect.SendSinglePageNew byteEncodedPageData


bodyToString : List (Html msg) -> String
bodyToString body =
    body |> List.map (HtmlPrinter.htmlToString Nothing) |> String.join "\n"


urlToRoute : ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage -> Url -> route
urlToRoute config url =
    if url.path |> String.startsWith "/____elm-pages-internal____" then
        config.notFoundRoute

    else
        config.urlToRoute url


toRedirectResponse :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage
    -> { b | path : UrlPath }
    -> RenderRequest.IncludeHtml
    -> { c | headers : List ( String, String ), statusCode : Int }
    -> { response | statusCode : Int, headers : List ( String, String ) }
    -> Maybe Effect
toRedirectResponse config serverRequestPayload includeHtml serverResponse responseMetadata =
    PageServerResponse.toRedirect responseMetadata
        |> Maybe.map
            (\_ ->
                let
                    ( _, byteEncodedPageData ) =
                        ( serverResponse.headers
                        , PageServerResponse.toRedirect serverResponse
                            |> Maybe.map
                                (\{ location } ->
                                    location
                                        |> ResponseSketch.Redirect
                                        |> config.encodeResponse
                                )
                            |> Maybe.withDefault (Bytes.Encode.unsignedInt8 0)
                            |> Bytes.Encode.encode
                        )
                in
                { route = serverRequestPayload.path |> UrlPath.toRelative
                , contentJson = Dict.empty
                , html = "This is intentionally blank HTML"
                , errors = []
                , head = []
                , title = "This is an intentionally blank title"
                , staticHttpCache = Dict.empty
                , is404 = False
                , statusCode =
                    case includeHtml of
                        RenderRequest.OnlyJson ->
                            -- if this is a redirect for a `content.dat`, we don't want to send an *actual* redirect status code because the redirect needs to be handled in Elm (not by the Browser)
                            200

                        RenderRequest.HtmlAndJson ->
                            responseMetadata.statusCode
                , headers = responseMetadata.headers |> combineHeaders
                }
                    |> ToJsPayload.PageProgress
                    |> Effect.SendSinglePageNew byteEncodedPageData
            )


combineHeaders : List ( String, String ) -> Dict String (List String)
combineHeaders headers =
    headers
        |> List.foldl
            (\( key, value ) dict ->
                Dict.update key
                    (Maybe.map ((::) value)
                        >> Maybe.withDefault [ value ]
                        >> Just
                    )
                    dict
            )
            Dict.empty
