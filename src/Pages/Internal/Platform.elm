module Pages.Internal.Platform exposing (Content, Flags, Model, Msg, Program, application, cliApplication)

import Browser
import Browser.Dom as Dom
import Browser.Navigation
import Head
import Html exposing (Html)
import Html.Attributes
import Html.Lazy
import Http
import Json.Decode as Decode
import Json.Encode
import NoMetadata exposing (NoMetadata(..), NoView(..))
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.HotReloadLoadingIndicator as HotReloadLoadingIndicator
import Pages.Internal.Platform.Cli
import Pages.Internal.String as String
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)
import Task
import Url exposing (Url)


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias Program userModel userMsg route pathKey =
    Platform.Program Flags (Model userModel route pathKey) (Msg userMsg)


mainView :
    (Url -> route)
    -> pathKey
    ->
        (List ( PagePath pathKey, NoMetadata )
         ->
            { path : PagePath pathKey
            , frontmatter : route
            }
         ->
            StaticHttp.Request
                { view :
                    userModel
                    -> NoView
                    ->
                        { title : String
                        , body : Html userMsg
                        }
                , head : List (Head.Tag pathKey)
                }
        )
    -> ModelDetails userModel
    -> { title : String, body : Html userMsg }
mainView urlToRoute pathKey pageView model =
    pageViewOrError urlToRoute pathKey pageView model model.contentCache


urlToPagePath : pathKey -> Url -> Url -> PagePath pathKey
urlToPagePath pathKey url baseUrl =
    url.path
        |> String.dropLeft (String.length baseUrl.path)
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")
        |> PagePath.build pathKey


normalizeUrl : Url -> Url -> Url
normalizeUrl baseUrl url =
    { url | path = url.path |> String.dropLeft (String.length baseUrl.path) |> String.chopForwardSlashes }


pageViewOrError :
    (Url -> route)
    -> pathKey
    ->
        (List ( PagePath pathKey, NoMetadata )
         ->
            { path : PagePath pathKey
            , frontmatter : route
            }
         ->
            StaticHttp.Request
                { view : userModel -> NoView -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
        )
    -> ModelDetails userModel
    -> ContentCache
    -> { title : String, body : Html userMsg }
pageViewOrError urlToRoute pathKey viewFn model cache =
    let
        urls =
            { currentUrl = model.url
            , baseUrl = model.baseUrl
            }
    in
    case ContentCache.lookup pathKey cache urls of
        Just ( pagePath, entry ) ->
            case entry of
                ContentCache.Parsed viewResult ->
                    let
                        viewFnResult =
                            { path = pagePath
                            , frontmatter = urlToRoute model.url |> Debug.log "pageViewOrError route"
                            }
                                |> viewFn []
                                |> (\request ->
                                        StaticHttpRequest.resolve ApplicationType.Browser
                                            request
                                            (viewResult.staticData
                                                |> Debug.log "StaticHttpRequest.resolve staticData"
                                            )
                                   )
                    in
                    case viewFnResult of
                        Ok okViewFn ->
                            okViewFn.view model.userModel NoView

                        Err error ->
                            { title = "Parsing error"
                            , body =
                                case error of
                                    StaticHttpRequest.DecoderError decoderError ->
                                        Html.div []
                                            [ Html.text "Could not parse static data. I encountered this decoder problem."
                                            , Html.pre [] [ Html.text decoderError ]
                                            ]

                                    StaticHttpRequest.MissingHttpResponse missingKey ->
                                        Html.div []
                                            [ Html.text "I'm missing some StaticHttp data for this page:"
                                            , Html.pre [] [ Html.text missingKey ]
                                            ]

                                    StaticHttpRequest.UserCalledStaticHttpFail message ->
                                        Html.div []
                                            [ Html.text "I ran into a call to `Pages.StaticHttp.fail` with message:"
                                            , Html.pre [] [ Html.text message ]
                                            ]
                            }

                ContentCache.NeedContent ->
                    { title = "elm-pages error", body = Html.text "Missing content" }

        Nothing ->
            { title = "Page not found"
            , body =
                Html.div []
                    [ Html.text "Page not found. Valid routes:\n\n"
                    , cache
                        |> ContentCache.routesForCache
                        |> String.join ", "
                        |> Html.text
                    ]
            }


view :
    (Url -> route)
    -> pathKey
    ->
        (List ( PagePath pathKey, NoMetadata )
         ->
            { path : PagePath pathKey
            , frontmatter : route
            }
         ->
            StaticHttp.Request
                { view : userModel -> NoView -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
        )
    -> ModelDetails userModel
    -> Browser.Document (Msg userMsg)
view urlToRoute pathKey viewFn model =
    let
        { title, body } =
            mainView urlToRoute pathKey viewFn model
    in
    { title = title |> Debug.log "title"
    , body =
        [ onViewChangeElement model.url
        , body |> Html.map UserMsg |> Html.map AppMsg
        , Html.Lazy.lazy2 loadingView model.phase model.hmrStatus
        ]
    }


loadingView : Phase -> HmrStatus -> Html msg
loadingView phase hmrStatus =
    case phase of
        DevClient isDebugMode ->
            (case hmrStatus of
                HmrLoading ->
                    True

                _ ->
                    False
            )
                |> HotReloadLoadingIndicator.view isDebugMode

        _ ->
            Html.text ""


onViewChangeElement currentUrl =
    -- this is a hidden tag
    -- it is used from the JS-side to reliably
    -- check when Elm has changed pages
    -- (and completed rendering the view)
    Html.div
        [ Html.Attributes.attribute "data-url" (Url.toString currentUrl)
        , Html.Attributes.attribute "display" "none"
        ]
        []


type alias Flags =
    Decode.Value


type alias ContentJson =
    { staticData : RequestsAndPending
    }


contentJsonDecoder : Decode.Decoder ContentJson
contentJsonDecoder =
    Decode.map ContentJson
        (Decode.field "staticData" RequestsAndPending.decoder)


init :
    (Url -> route)
    -> pathKey
    ->
        (Maybe
            { metadata : route
            , path :
                { path : PagePath pathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            }
         -> ( userModel, Cmd userMsg )
        )
    -> Flags
    -> Url
    -> Browser.Navigation.Key
    -> ( ModelDetails userModel, Cmd (AppMsg userMsg) )
init urlToRoute pathKey initUserModel flags url key =
    let
        contentCache =
            ContentCache.init
                (Maybe.map
                    (\cj ->
                        { contentJson = cj
                        , initialUrl = url |> normalizeUrl baseUrl
                        }
                    )
                    contentJson
                )

        contentJson =
            flags
                |> Decode.decodeValue (Decode.field "contentJson" contentJsonDecoder)
                |> Result.toMaybe

        baseUrl =
            flags
                |> Decode.decodeValue (Decode.field "baseUrl" Decode.string)
                |> Result.toMaybe
                |> Maybe.andThen Url.fromString
                |> Maybe.withDefault url

        urls =
            -- @@@
            { currentUrl = url -- |> normalizeUrl baseUrl
            , baseUrl = baseUrl
            }
    in
    case contentCache of
        Ok okCache ->
            let
                phase =
                    case
                        Decode.decodeValue
                            (Decode.map3 (\a b c -> ( a, b, c ))
                                (Decode.field "isPrerendering" Decode.bool)
                                (Decode.field "isDevServer" Decode.bool)
                                (Decode.field "isElmDebugMode" Decode.bool)
                            )
                            flags
                    of
                        Ok ( True, _, _ ) ->
                            Prerender

                        Ok ( False, True, isElmDebugMode ) ->
                            DevClient isElmDebugMode

                        Ok ( False, False, _ ) ->
                            ProdClient

                        Err _ ->
                            DevClient False

                ( userModel, userCmd ) =
                    Maybe.map2
                        (\pagePath _ ->
                            { path =
                                { path = pagePath
                                , query = url.query
                                , fragment = url.fragment
                                }
                            , metadata = urlToRoute url
                            }
                        )
                        maybePagePath
                        maybeMetadata
                        |> initUserModel

                cmd =
                    [ userCmd
                        |> Cmd.map UserMsg
                        |> Just
                    , contentCache
                        |> ContentCache.lazyLoad urls
                        |> Task.attempt UpdateCache
                        |> Just
                    ]
                        |> List.filterMap identity
                        |> Cmd.batch

                ( maybePagePath, maybeMetadata ) =
                    case ContentCache.lookupMetadata pathKey (Ok okCache) urls of
                        Just pagePath ->
                            ( Just pagePath, Just NoMetadata )

                        Nothing ->
                            ( Nothing, Nothing )
            in
            ( { key = key
              , url = url
              , baseUrl = baseUrl
              , userModel = userModel
              , contentCache = contentCache
              , phase = phase
              , hmrStatus = HmrLoaded
              }
            , cmd
            )

        Err _ ->
            let
                ( userModel, userCmd ) =
                    initUserModel Nothing
            in
            ( { key = key
              , url = url
              , baseUrl = baseUrl
              , userModel = userModel
              , contentCache = contentCache
              , phase = DevClient False
              , hmrStatus = HmrLoaded
              }
            , Cmd.batch
                [ userCmd |> Cmd.map UserMsg
                ]
              -- TODO handle errors better
            )


encodeHeads : List String -> String -> String -> List (Head.Tag pathKey) -> Json.Encode.Value
encodeHeads allRoutes canonicalSiteUrl currentPagePath head =
    Json.Encode.object
        [ ( "head", Json.Encode.list (Head.toJson canonicalSiteUrl currentPagePath) head )
        , ( "allRoutes", Json.Encode.list Json.Encode.string allRoutes )
        ]


type Msg userMsg
    = AppMsg (AppMsg userMsg)
    | CliMsg Pages.Internal.Platform.Cli.Msg


type AppMsg userMsg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | UserMsg userMsg
    | UpdateCache (Result Http.Error ContentCache)
    | UpdateCacheAndUrl Url (Result Http.Error ContentCache)
    | PageScrollComplete
    | HotReloadComplete ContentJson
    | StartingHotReload


type Model userModel route pathKey
    = Model (ModelDetails userModel)
    | CliModel (Pages.Internal.Platform.Cli.Model pathKey route)


type alias ModelDetails userModel =
    { key : Browser.Navigation.Key
    , url : Url
    , baseUrl : Url
    , contentCache : ContentCache
    , userModel : userModel
    , phase : Phase
    , hmrStatus : HmrStatus
    }


type Phase
    = Prerender
    | DevClient Bool
    | ProdClient


update :
    (Url -> route)
    -> List String
    -> String
    ->
        (List ( PagePath pathKey, NoMetadata )
         ->
            { path : PagePath pathKey
            , frontmatter : route
            }
         ->
            StaticHttp.Request
                { view : userModel -> NoView -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
        )
    -> pathKey
    ->
        Maybe
            ({ path : PagePath pathKey
             , query : Maybe String
             , fragment : Maybe String
             , metadata : route
             }
             -> userMsg
            )
    -> (Json.Encode.Value -> Cmd Never)
    -> (userMsg -> userModel -> ( userModel, Cmd userMsg ))
    -> Msg userMsg
    -> ModelDetails userModel
    -> ( ModelDetails userModel, Cmd (AppMsg userMsg) )
update urlToRoute allRoutes canonicalSiteUrl viewFunction pathKey maybeOnPageChangeMsg toJsPort userUpdate msg model =
    case msg of
        AppMsg appMsg ->
            case appMsg of
                LinkClicked urlRequest ->
                    case urlRequest of
                        Browser.Internal url ->
                            let
                                navigatingToSamePage =
                                    (url.path == model.url.path) && (url /= model.url)
                            in
                            if navigatingToSamePage then
                                -- this is a workaround for an issue with anchor fragment navigation
                                -- see https://github.com/elm/browser/issues/39
                                ( model, Browser.Navigation.load (Url.toString url) )

                            else
                                ( model, Browser.Navigation.pushUrl model.key (Url.toString url) )

                        Browser.External href ->
                            ( model, Browser.Navigation.load href )

                UrlChanged url ->
                    let
                        navigatingToSamePage =
                            (url.path == model.url.path) && (url /= model.url)

                        urls =
                            { currentUrl = url
                            , baseUrl = model.baseUrl
                            }
                    in
                    ( model
                    , if navigatingToSamePage then
                        -- this saves a few CPU cycles, but also
                        -- makes sure we don't send an UpdateCacheAndUrl
                        -- which scrolls to the top after page changes.
                        -- This is important because we may have just scrolled
                        -- to a specific page location for an anchor link.
                        Cmd.none

                      else
                        model.contentCache
                            |> ContentCache.lazyLoad urls
                            |> Task.attempt (UpdateCacheAndUrl url)
                    )

                UserMsg userMsg ->
                    let
                        ( userModel, userCmd ) =
                            userUpdate userMsg model.userModel
                    in
                    ( { model | userModel = userModel }, userCmd |> Cmd.map UserMsg )

                UpdateCache cacheUpdateResult ->
                    case cacheUpdateResult |> Debug.log "cacheUpdateResult" of
                        -- TODO can there be race conditions here? Might need to set something in the model
                        -- to keep track of the last url change
                        Ok updatedCache ->
                            let
                                urls =
                                    { currentUrl = model.url
                                    , baseUrl = model.baseUrl
                                    }

                                maybeCmd =
                                    case ContentCache.lookup pathKey updatedCache urls of
                                        Just ( pagePath, entry ) ->
                                            case entry of
                                                ContentCache.Parsed viewResult ->
                                                    headFn pagePath (urlToRoute model.url) viewResult.staticData
                                                        |> Result.map .head
                                                        |> Result.toMaybe
                                                        |> Maybe.map (encodeHeads allRoutes canonicalSiteUrl model.url.path)
                                                        |> Maybe.map toJsPort

                                                ContentCache.NeedContent ->
                                                    Nothing

                                        Nothing ->
                                            Nothing

                                headFn pagePath frontmatter staticDataThing =
                                    viewFunction
                                        []
                                        { path = pagePath, frontmatter = frontmatter }
                                        |> (\request ->
                                                StaticHttpRequest.resolve ApplicationType.Browser request staticDataThing
                                           )
                            in
                            ( { model | contentCache = updatedCache }
                            , maybeCmd
                                |> Maybe.map (Cmd.map never)
                                |> Maybe.withDefault Cmd.none
                            )

                        Err _ ->
                            -- TODO handle error
                            ( model, Cmd.none )

                UpdateCacheAndUrl url cacheUpdateResult ->
                    case cacheUpdateResult |> Debug.log "updateCacheResult" of
                        -- TODO can there be race conditions here? Might need to set something in the model
                        -- to keep track of the last url change
                        Ok updatedCache ->
                            let
                                ( userModel, userCmd ) =
                                    case maybeOnPageChangeMsg of
                                        Just onPageChangeMsg ->
                                            userUpdate
                                                (onPageChangeMsg
                                                    { path = urlToPagePath pathKey url model.baseUrl
                                                    , query = url.query
                                                    , fragment = url.fragment
                                                    , metadata = urlToRoute url
                                                    }
                                                )
                                                model.userModel

                                        _ ->
                                            ( model.userModel, Cmd.none )
                            in
                            ( { model
                                | url = url |> Debug.log "@@@ url"
                                , contentCache = updatedCache
                                , userModel = userModel
                              }
                            , Cmd.batch
                                [ userCmd |> Cmd.map UserMsg
                                , Task.perform (\_ -> PageScrollComplete) (Dom.setViewport 0 0)
                                ]
                            )

                        Err _ ->
                            -- TODO handle error
                            ( { model | url = url }, Cmd.none )

                PageScrollComplete ->
                    ( model, Cmd.none )

                HotReloadComplete contentJson ->
                    ( { model
                        | contentCache = ContentCache.init (Just { contentJson = contentJson, initialUrl = model.url })
                        , hmrStatus = HmrLoaded
                      }
                    , Cmd.none
                    )

                StartingHotReload ->
                    ( { model | hmrStatus = HmrLoading }, Cmd.none )

        CliMsg _ ->
            ( model, Cmd.none )


type HmrStatus
    = HmrLoading
    | HmrLoaded


application :
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
    , urlToRoute : Url -> route
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
                { view : userModel -> NoView -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
    , document : Pages.Document.Document NoMetadata NoView
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , manifest : Manifest.Config pathKey
    , generateFiles :
        List
            { path : PagePath pathKey
            , frontmatter : NoMetadata
            , body : String
            }
        ->
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
    --    -> Program userModel userMsg metadata view
    -> Platform.Program Flags (Model userModel route pathKey) (Msg userMsg)
application config =
    Browser.application
        { init =
            \flags url key ->
                init config.urlToRoute config.pathKey config.init flags url key
                    |> Tuple.mapFirst Model
                    |> Tuple.mapSecond (Cmd.map AppMsg)
        , view =
            \outerModel ->
                case outerModel of
                    Model model ->
                        view config.urlToRoute config.pathKey config.view model

                    CliModel _ ->
                        { title = "Error"
                        , body = [ Html.text "Unexpected state" ]
                        }
        , update =
            \msg outerModel ->
                case outerModel of
                    Model model ->
                        let
                            userUpdate =
                                case model.phase of
                                    Prerender ->
                                        noOpUpdate

                                    _ ->
                                        config.update

                            noOpUpdate =
                                \_ userModel ->
                                    ( userModel, Cmd.none )

                            allRoutes =
                                config.content
                                    |> List.map Tuple.first
                                    |> List.map (String.join "/")
                        in
                        update config.urlToRoute allRoutes config.canonicalSiteUrl config.view config.pathKey config.onPageChange config.toJsPort userUpdate msg model
                            |> Tuple.mapFirst Model
                            |> Tuple.mapSecond (Cmd.map AppMsg)

                    CliModel _ ->
                        ( outerModel, Cmd.none )
        , subscriptions =
            \outerModel ->
                case outerModel of
                    Model model ->
                        let
                            urls =
                                { currentUrl = model.url
                                , baseUrl = model.baseUrl
                                }

                            maybePagePath =
                                case ContentCache.lookupMetadata config.pathKey model.contentCache urls of
                                    Just pagePath ->
                                        Just pagePath

                                    Nothing ->
                                        Nothing

                            userSub =
                                Maybe.map
                                    (\path ->
                                        config.subscriptions NoMetadata path model.userModel
                                            |> Sub.map UserMsg
                                            |> Sub.map AppMsg
                                    )
                                    maybePagePath
                                    |> Maybe.withDefault Sub.none
                        in
                        Sub.batch
                            [ userSub
                            , config.fromJsPort
                                |> Sub.map
                                    (\decodeValue ->
                                        case decodeValue |> Decode.decodeValue (Decode.field "action" Decode.string) of
                                            Ok "hmr-check" ->
                                                AppMsg StartingHotReload

                                            _ ->
                                                case decodeValue |> Decode.decodeValue (Decode.field "contentJson" contentJsonDecoder) of
                                                    Ok contentJson ->
                                                        AppMsg (HotReloadComplete contentJson)

                                                    Err _ ->
                                                        -- TODO should be no message here
                                                        AppMsg StartingHotReload
                                    )
                            ]

                    CliModel _ ->
                        Sub.none
        , onUrlChange = UrlChanged >> AppMsg
        , onUrlRequest = LinkClicked >> AppMsg
        }


cliApplication :
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
    , urlToRoute : Url -> route
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
                { view : userModel -> NoView -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
    , document : Pages.Document.Document NoMetadata NoView
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , manifest : Manifest.Config pathKey
    , generateFiles :
        List
            { path : PagePath pathKey
            , frontmatter : NoMetadata
            , body : String
            }
        ->
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
    -> Program userModel userMsg route pathKey
cliApplication =
    Pages.Internal.Platform.Cli.cliApplication CliMsg
        (\msg ->
            case msg of
                CliMsg cliMsg ->
                    Just cliMsg

                _ ->
                    Nothing
        )
        CliModel
        (\model ->
            case model of
                CliModel cliModel ->
                    Just cliModel

                _ ->
                    Nothing
        )
