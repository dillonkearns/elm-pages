module Pages.Internal.Platform exposing (Flags, Model, Msg, Program, application, cliApplication)

import Browser
import Browser.Dom as Dom
import Browser.Navigation
import BuildError exposing (BuildError)
import Html exposing (Html)
import Html.Attributes
import Http
import Json.Decode as Decode
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Cli
import Pages.Internal.String as String
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)
import Task
import Url exposing (Url)


type alias Program userModel userMsg route pageStaticData sharedStaticData =
    Platform.Program Flags (Model userModel route pageStaticData sharedStaticData) (Msg userMsg)


mainView :
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> ModelDetails userModel pageStaticData sharedStaticData
    -> { title : String, body : Html userMsg }
mainView config model =
    let
        urls =
            { currentUrl = model.url
            , baseUrl = model.baseUrl
            }
    in
    case ContentCache.lookup model.contentCache urls of
        Just ( pagePath, entry ) ->
            (config.view
                { path = pagePath
                , frontmatter = config.urlToRoute model.url
                }
                model.sharedStaticData
                model.pageStaticData
                |> .view
            )
                model.userModel

        Nothing ->
            { title = "Page not found"
            , body =
                Html.div [] [ Html.text "Page not found." ]
            }


urlToPagePath : Url -> Url -> PagePath
urlToPagePath url baseUrl =
    url.path
        |> String.dropLeft (String.length baseUrl.path)
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")
        |> PagePath.build


view :
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> ModelDetails userModel pageStaticData sharedStaticData
    -> Browser.Document (Msg userMsg)
view config model =
    let
        { title, body } =
            mainView config model
    in
    { title = title
    , body =
        [ onViewChangeElement model.url
        , body |> Html.map UserMsg |> Html.map AppMsg
        ]
    }


onViewChangeElement : Url -> Html msg
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
    ProgramConfig userMsg userModel route staticData pageStaticData sharedStaticData
    -> Flags
    -> Url
    -> Browser.Navigation.Key
    -> ( ModelDetails userModel pageStaticData sharedStaticData, Cmd (AppMsg userMsg) )
init config flags url key =
    let
        contentCache =
            ContentCache.init
                (Maybe.map
                    (\cj ->
                        -- TODO parse the page path to a list here
                        ( urls
                        , cj
                        )
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

                justContentJson : RequestsAndPending
                justContentJson =
                    case contentJson of
                        Nothing ->
                            Debug.todo "Expected content.json"

                        Just justValue ->
                            justValue.staticData

                pageStaticDataResult : Result BuildError pageStaticData
                pageStaticDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        (config.staticData (config.urlToRoute url))
                        justContentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError url.path)

                pageStaticData : pageStaticData
                pageStaticData =
                    case pageStaticDataResult of
                        Ok okPageStaticData ->
                            okPageStaticData

                        Err error ->
                            Debug.todo (BuildError.errorToString error)

                sharedStaticDataResult : Result BuildError sharedStaticData
                sharedStaticDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        config.sharedStaticData
                        justContentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError url.path)

                sharedStaticData : sharedStaticData
                sharedStaticData =
                    case sharedStaticDataResult of
                        Ok okSharedStaticData ->
                            okSharedStaticData

                        Err error ->
                            Debug.todo (BuildError.errorToString error)

                ( userModel, userCmd ) =
                    Maybe.map
                        (\pagePath ->
                            { path =
                                { path = pagePath
                                , query = url.query
                                , fragment = url.fragment
                                }
                            , metadata = config.urlToRoute url
                            }
                        )
                        maybePagePath
                        |> config.init pageStaticData (Just key)

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

                maybePagePath =
                    case ContentCache.lookupMetadata (Ok okCache) urls of
                        Just pagePath ->
                            Just pagePath

                        Nothing ->
                            Nothing
            in
            ( { key = key
              , url = url
              , baseUrl = baseUrl
              , userModel = userModel
              , contentCache = contentCache
              , phase = phase
              , pageStaticData = pageStaticData
              , sharedStaticData = sharedStaticData
              }
            , cmd
            )

        Err _ ->
            let
                pageStaticData =
                    Debug.todo ""

                sharedStaticData =
                    Debug.todo ""

                ( userModel, userCmd ) =
                    config.init pageStaticData (Just key) Nothing
            in
            ( { key = key
              , url = url
              , baseUrl = baseUrl
              , userModel = userModel
              , contentCache = contentCache
              , phase = DevClient False
              , pageStaticData = pageStaticData
              , sharedStaticData = sharedStaticData
              }
            , Cmd.batch
                [ userCmd |> Cmd.map UserMsg
                ]
              -- TODO handle errors better
            )


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


type Model userModel route pageStaticData sharedStaticData
    = Model (ModelDetails userModel pageStaticData sharedStaticData)
    | CliModel (Pages.Internal.Platform.Cli.Model route)


type alias ModelDetails userModel pageStaticData sharedStaticData =
    { key : Browser.Navigation.Key
    , url : Url
    , baseUrl : Url
    , contentCache : ContentCache
    , userModel : userModel
    , phase : Phase
    , pageStaticData : pageStaticData
    , sharedStaticData : sharedStaticData
    }


type Phase
    = Prerender
    | DevClient Bool
    | ProdClient


update :
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> (Maybe Browser.Navigation.Key -> userMsg -> userModel -> ( userModel, Cmd userMsg ))
    -> Msg userMsg
    -> ModelDetails userModel pageStaticData sharedStaticData
    -> ( ModelDetails userModel pageStaticData sharedStaticData, Cmd (AppMsg userMsg) )
update config userUpdate msg model =
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
                            userUpdate (Just model.key) userMsg model.userModel
                    in
                    ( { model | userModel = userModel }, userCmd |> Cmd.map UserMsg )

                UpdateCache cacheUpdateResult ->
                    case cacheUpdateResult of
                        -- TODO can there be race conditions here? Might need to set something in the model
                        -- to keep track of the last url change
                        Ok updatedCache ->
                            ( { model | contentCache = updatedCache }
                            , Cmd.none
                            )

                        Err _ ->
                            -- TODO handle error
                            ( model, Cmd.none )

                UpdateCacheAndUrl url cacheUpdateResult ->
                    case cacheUpdateResult of
                        -- TODO can there be race conditions here? Might need to set something in the model
                        -- to keep track of the last url change
                        Ok updatedCache ->
                            let
                                ( userModel, userCmd ) =
                                    case config.onPageChange of
                                        Just onPageChangeMsg ->
                                            userUpdate (Just model.key)
                                                (onPageChangeMsg
                                                    { path = urlToPagePath url model.baseUrl
                                                    , query = url.query
                                                    , fragment = url.fragment
                                                    , metadata = config.urlToRoute url
                                                    }
                                                )
                                                model.userModel

                                        _ ->
                                            ( model.userModel, Cmd.none )

                                urls =
                                    { currentUrl = model.url, baseUrl = model.baseUrl }
                            in
                            ( { model
                                | url = url
                                , contentCache = updatedCache
                                , userModel = userModel
                                , pageStaticData =
                                    ContentCache.lookupContentJson updatedCache urls
                                        |> Maybe.andThen
                                            (\requests ->
                                                StaticHttpRequest.resolve ApplicationType.Browser
                                                    (config.staticData (config.urlToRoute url))
                                                    requests
                                                    |> Result.toMaybe
                                             -- TODO handle Maybe/Err cases
                                            )
                                        |> Maybe.withDefault model.pageStaticData

                                -- TODO update pageStaticData here?
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
                    let
                        urls =
                            { currentUrl = model.url, baseUrl = model.baseUrl }
                    in
                    ( { model
                        | contentCache =
                            ContentCache.init (Just ( urls, contentJson ))
                      }
                    , Cmd.none
                    )

                StartingHotReload ->
                    ( model, Cmd.none )

        CliMsg _ ->
            ( model, Cmd.none )


application :
    ProgramConfig userMsg userModel route staticData pageStaticData sharedStaticData
    -> Platform.Program Flags (Model userModel route pageStaticData sharedStaticData) (Msg userMsg)
application config =
    Browser.application
        { init =
            \flags url key ->
                init config flags url key
                    |> Tuple.mapFirst Model
                    |> Tuple.mapSecond (Cmd.map AppMsg)
        , view =
            \outerModel ->
                case outerModel of
                    Model model ->
                        view config model

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
                                        config.update model.pageStaticData

                            noOpUpdate =
                                \_ _ userModel ->
                                    ( userModel, Cmd.none )
                        in
                        update config userUpdate msg model
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
                                { currentUrl = model.url, baseUrl = model.baseUrl }

                            maybePagePath =
                                case ContentCache.lookupMetadata model.contentCache urls of
                                    Just pagePath ->
                                        Just pagePath

                                    Nothing ->
                                        Nothing

                            userSub =
                                Maybe.map
                                    (\path ->
                                        config.subscriptions (path |> pathToUrl |> config.urlToRoute) path model.userModel
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
    ProgramConfig userMsg userModel route staticData pageStaticData sharedStaticData
    -> Program userModel userMsg route pageStaticData sharedStaticData
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


pathToUrl : PagePath -> Url
pathToUrl path =
    { protocol = Url.Https
    , host = "TODO"
    , port_ = Nothing
    , path = path |> PagePath.toString
    , query = Nothing
    , fragment = Nothing
    }
