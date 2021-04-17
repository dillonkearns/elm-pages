module Pages.Internal.Platform exposing (Flags, Model, Msg, Program, application)

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
import Pages.Internal.String as String
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)
import Task
import Url exposing (Url)


type alias Program userModel userMsg pageStaticData sharedStaticData =
    Platform.Program Flags (Model userModel pageStaticData sharedStaticData) (Msg userMsg)


mainView :
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> Model userModel pageStaticData sharedStaticData
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
            case model.pageData of
                Ok pageData ->
                    (config.view
                        { path = pagePath
                        , frontmatter = config.urlToRoute model.url
                        }
                        pageData.sharedStaticData
                        pageData.pageStaticData
                        |> .view
                    )
                        pageData.userModel

                Err error ->
                    { title = "Page Data Error"
                    , body =
                        Html.div [] [ Html.text error ]
                    }

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
    -> Model userModel pageStaticData sharedStaticData
    -> Browser.Document (Msg userMsg)
view config model =
    let
        { title, body } =
            mainView config model
    in
    { title = title
    , body =
        [ onViewChangeElement model.url
        , body |> Html.map UserMsg
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
    -> ( Model userModel pageStaticData sharedStaticData, Cmd (Msg userMsg) )
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
    case contentJson |> Maybe.map .staticData of
        Just justContentJson ->
            let
                pageStaticDataResult : Result BuildError pageStaticData
                pageStaticDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        (config.staticData (config.urlToRoute url))
                        justContentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError url.path)

                sharedStaticDataResult : Result BuildError sharedStaticData
                sharedStaticDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        config.sharedStaticData
                        justContentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError url.path)

                maybePagePath =
                    case ContentCache.lookupMetadata contentCache urls of
                        Just pagePath ->
                            Just pagePath

                        Nothing ->
                            Nothing
            in
            case Result.map2 Tuple.pair sharedStaticDataResult pageStaticDataResult of
                Ok ( sharedStaticData, pageStaticData ) ->
                    let
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
                    in
                    ( { key = key
                      , url = url
                      , baseUrl = baseUrl
                      , contentCache = contentCache
                      , pageData =
                            Ok
                                { pageStaticData = pageStaticData
                                , sharedStaticData = sharedStaticData
                                , userModel = userModel
                                }
                      }
                    , cmd
                    )

                Err error ->
                    ( { key = key
                      , url = url
                      , baseUrl = baseUrl
                      , contentCache = contentCache
                      , pageData = BuildError.errorToString error |> Err
                      }
                    , Cmd.none
                    )

        Nothing ->
            ( { key = key
              , url = url
              , baseUrl = baseUrl
              , contentCache = contentCache
              , pageData = Err "TODO"
              }
            , Cmd.none
            )


type Msg userMsg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | UserMsg userMsg
    | UpdateCache (Result Http.Error ( Url, ContentJson, ContentCache ))
    | UpdateCacheAndUrl Url (Result Http.Error ( Url, ContentJson, ContentCache ))
    | PageScrollComplete
    | HotReloadComplete ContentJson
    | StartingHotReload


type alias Model userModel pageStaticData sharedStaticData =
    { key : Browser.Navigation.Key
    , url : Url
    , baseUrl : Url
    , contentCache : ContentCache
    , pageData :
        Result
            String
            { userModel : userModel
            , pageStaticData : pageStaticData
            , sharedStaticData : sharedStaticData
            }
    }


update :
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> Msg userMsg
    -> Model userModel pageStaticData sharedStaticData
    -> ( Model userModel pageStaticData sharedStaticData, Cmd (Msg userMsg) )
update config appMsg model =
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
            case model.pageData of
                Ok pageData ->
                    let
                        ( userModel, userCmd ) =
                            config.update pageData.pageStaticData (Just model.key) userMsg pageData.userModel

                        updatedPageData =
                            Ok { pageData | userModel = userModel }
                    in
                    ( { model | pageData = updatedPageData }, userCmd |> Cmd.map UserMsg )

                Err error ->
                    ( model, Cmd.none )

        UpdateCache cacheUpdateResult ->
            case cacheUpdateResult of
                -- TODO can there be race conditions here? Might need to set something in the model
                -- to keep track of the last url change
                Ok ( url, contentJson, updatedCache ) ->
                    ( { model | contentCache = updatedCache }
                    , Cmd.none
                    )

                Err _ ->
                    -- TODO handle error
                    ( model, Cmd.none )

        UpdateCacheAndUrl url cacheUpdateResult ->
            case
                Result.map2 Tuple.pair (cacheUpdateResult |> Result.mapError (\error -> "Http error")) model.pageData
            of
                -- TODO can there be race conditions here? Might need to set something in the model
                -- to keep track of the last url change
                Ok ( ( _, contentJson, updatedCache ), pageData ) ->
                    let
                        ( userModel, userCmd ) =
                            case config.onPageChange of
                                Just onPageChangeMsg ->
                                    config.update
                                        pageData.pageStaticData
                                        (Just model.key)
                                        (onPageChangeMsg
                                            { path = urlToPagePath url model.baseUrl
                                            , query = url.query
                                            , fragment = url.fragment
                                            , metadata = config.urlToRoute url
                                            }
                                        )
                                        pageData.userModel

                                _ ->
                                    ( pageData.userModel, Cmd.none )
                    in
                    ( { model
                        | url = url
                        , contentCache = updatedCache
                        , pageData =
                            StaticHttpRequest.resolve ApplicationType.Browser
                                (config.staticData (config.urlToRoute url))
                                contentJson.staticData
                                |> Result.mapError (\_ -> "Http error")
                                |> Result.map
                                    (\pageStaticData ->
                                        { userModel = userModel
                                        , sharedStaticData = pageData.sharedStaticData
                                        , pageStaticData = pageStaticData
                                        }
                                    )
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

                pageStaticDataResult : Result BuildError pageStaticData
                pageStaticDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        (config.staticData (config.urlToRoute model.url))
                        contentJson.staticData
                        |> Result.mapError (StaticHttpRequest.toBuildError model.url.path)

                sharedStaticDataResult : Result BuildError sharedStaticData
                sharedStaticDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        config.sharedStaticData
                        contentJson.staticData
                        |> Result.mapError (StaticHttpRequest.toBuildError model.url.path)

                maybePagePath =
                    case ContentCache.lookupMetadata model.contentCache urls of
                        Just pagePath ->
                            Just pagePath

                        Nothing ->
                            Nothing
            in
            case Result.map2 Tuple.pair sharedStaticDataResult pageStaticDataResult of
                Ok ( sharedStaticData, pageStaticData ) ->
                    ( { model
                        | contentCache =
                            ContentCache.init (Just ( urls, contentJson ))
                        , pageData =
                            model.pageData
                                |> Result.map
                                    (\previousPageData ->
                                        { pageStaticData = pageStaticData
                                        , sharedStaticData = sharedStaticData
                                        , userModel = previousPageData.userModel
                                        }
                                    )
                      }
                    , Cmd.none
                    )

                Err error ->
                    ( { model
                        | contentCache =
                            ContentCache.init (Just ( urls, contentJson ))
                      }
                    , Cmd.none
                    )

        StartingHotReload ->
            ( model, Cmd.none )


application :
    ProgramConfig userMsg userModel route staticData pageStaticData sharedStaticData
    -> Platform.Program Flags (Model userModel pageStaticData sharedStaticData) (Msg userMsg)
application config =
    Browser.application
        { init =
            \flags url key ->
                init config flags url key
        , view = view config
        , update = update config
        , subscriptions =
            \model ->
                let
                    urls =
                        { currentUrl = model.url, baseUrl = model.baseUrl }

                    maybePagePath =
                        case ContentCache.lookupMetadata model.contentCache urls of
                            Just pagePath ->
                                Just pagePath

                            Nothing ->
                                Nothing
                in
                case model.pageData of
                    Ok pageData ->
                        Sub.batch
                            [ Maybe.map
                                (\path ->
                                    config.subscriptions (path |> pathToUrl |> config.urlToRoute) path pageData.userModel
                                        |> Sub.map UserMsg
                                )
                                maybePagePath
                                |> Maybe.withDefault Sub.none
                            , config.fromJsPort
                                |> Sub.map
                                    (\decodeValue ->
                                        case decodeValue |> Decode.decodeValue (Decode.field "contentJson" contentJsonDecoder) of
                                            Ok contentJson ->
                                                HotReloadComplete contentJson

                                            Err _ ->
                                                -- TODO should be no message here
                                                StartingHotReload
                                    )
                            ]

                    Err _ ->
                        Sub.none
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


pathToUrl : PagePath -> Url
pathToUrl path =
    { protocol = Url.Https
    , host = "TODO"
    , port_ = Nothing
    , path = path |> PagePath.toString
    , query = Nothing
    , fragment = Nothing
    }
