module Pages.Internal.Platform exposing (Flags, Model, Msg, Program, application)

{-| Exposed for internal use only (used in generated code).

@docs Flags, Model, Msg, Program, application

-}

import AriaLiveAnnouncer
import Browser
import Browser.Dom as Dom
import Browser.Navigation
import BuildError exposing (BuildError)
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Json.Decode as Decode
import Json.Encode
import PageServerResponse exposing (PageServerResponse)
import Pages.ContentCache as ContentCache exposing (ContentCache, ContentJson, contentJsonDecoder)
import Pages.Flags
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.NotFoundReason
import Pages.Internal.String as String
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttpRequest as StaticHttpRequest
import Path exposing (Path)
import QueryParams
import Task
import Url exposing (Url)


{-| -}
type alias Program userModel userMsg pageData sharedData =
    Platform.Program Flags (Model userModel pageData sharedData) (Msg userMsg)


mainView :
    ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model userModel pageData sharedData
    -> { title : String, body : Html userMsg }
mainView config model =
    let
        urls : { currentUrl : Url, basePath : List String }
        urls =
            { currentUrl = model.url
            , basePath = config.basePath
            }
    in
    case ContentCache.notFoundReason model.contentCache urls of
        Just notFoundReason ->
            Pages.Internal.NotFoundReason.document config.pathPatterns notFoundReason

        Nothing ->
            case model.pageData of
                Ok pageData ->
                    (config.view
                        { path = ContentCache.pathForUrl urls |> Path.join
                        , route = config.urlToRoute model.url
                        }
                        Nothing
                        pageData.sharedData
                        pageData.pageData
                        |> .view
                    )
                        pageData.userModel

                Err error ->
                    { title = "Page Data Error"
                    , body =
                        Html.div [] [ Html.text error ]
                    }


urlsToPagePath :
    { currentUrl : Url, basePath : List String }
    -> Path
urlsToPagePath urls =
    urls.currentUrl.path
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")
        |> List.drop (List.length urls.basePath)
        |> Path.join


view :
    ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model userModel pageData sharedData
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
        , AriaLiveAnnouncer.view model.ariaNavigationAnnouncement
        ]
    }


onViewChangeElement : Url -> Html msg
onViewChangeElement currentUrl =
    -- this is a hidden tag
    -- it is used from the JS-side to reliably
    -- check when Elm has changed pages
    -- (and completed rendering the view)
    Html.div
        [ Attr.attribute "data-url" (Url.toString currentUrl)
        , Attr.attribute "display" "none"
        ]
        []


{-| -}
type alias Flags =
    Decode.Value


{-| -}
init :
    ProgramConfig userMsg userModel route staticData pageData sharedData
    -> Flags
    -> Url
    -> Browser.Navigation.Key
    -> ( Model userModel pageData sharedData, Cmd (Msg userMsg) )
init config flags url key =
    let
        contentCache : ContentCache
        contentCache =
            ContentCache.init
                (Maybe.map
                    (\cj ->
                        ( currentPath
                        , cj
                        )
                    )
                    contentJson
                )

        currentPath : List String
        currentPath =
            flags
                |> Decode.decodeValue
                    (Decode.at [ "contentJson", "path" ]
                        (Decode.string
                            |> Decode.map Path.fromString
                            |> Decode.map Path.toSegments
                        )
                    )
                |> Result.mapError Decode.errorToString
                |> Result.toMaybe
                |> Maybe.withDefault []

        contentJson : Maybe ContentJson
        contentJson =
            flags
                |> Decode.decodeValue (Decode.field "contentJson" contentJsonDecoder)
                |> Result.toMaybe

        urls : { currentUrl : Url, basePath : List String }
        urls =
            { currentUrl = url
            , basePath = config.basePath
            }
    in
    case contentJson |> Maybe.map .staticData of
        Just justContentJson ->
            let
                pageDataResult : Result BuildError (PageServerResponse pageData)
                pageDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        (config.data (config.urlToRoute url))
                        justContentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError url.path)

                sharedDataResult : Result BuildError sharedData
                sharedDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        config.sharedData
                        justContentJson
                        |> Result.mapError (StaticHttpRequest.toBuildError url.path)

                pagePath : Path
                pagePath =
                    urlsToPagePath urls
            in
            case Result.map2 Tuple.pair sharedDataResult pageDataResult of
                Ok ( sharedData, pageData_ ) ->
                    case pageData_ of
                        PageServerResponse.RenderPage _ pageData ->
                            let
                                userFlags : Pages.Flags.Flags
                                userFlags =
                                    flags
                                        |> Decode.decodeValue
                                            (Decode.field "userFlags" Decode.value)
                                        |> Result.withDefault Json.Encode.null
                                        |> Pages.Flags.BrowserFlags

                                ( userModel, userCmd ) =
                                    Just
                                        { path =
                                            { path = pagePath
                                            , query = url.query
                                            , fragment = url.fragment
                                            }
                                        , metadata = config.urlToRoute url
                                        , pageUrl =
                                            Just
                                                { protocol = url.protocol
                                                , host = url.host
                                                , port_ = url.port_
                                                , path = pagePath
                                                , query = url.query |> Maybe.map QueryParams.fromString
                                                , fragment = url.fragment
                                                }
                                        }
                                        |> config.init userFlags sharedData pageData (Just key)

                                cmd : Cmd (Msg userMsg)
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

                                initialModel : Model userModel pageData sharedData
                                initialModel =
                                    { key = key
                                    , url = url
                                    , contentCache = contentCache
                                    , pageData =
                                        Ok
                                            { pageData = pageData
                                            , sharedData = sharedData
                                            , userModel = userModel
                                            }
                                    , ariaNavigationAnnouncement = ""
                                    , userFlags = flags
                                    }
                            in
                            ( { initialModel
                                | ariaNavigationAnnouncement = mainView config initialModel |> .title
                              }
                            , cmd
                            )

                        _ ->
                            ( { key = key
                              , url = url
                              , contentCache = contentCache
                              , pageData = "Didn't expect to render page for API response" |> Err
                              , ariaNavigationAnnouncement = "Error"
                              , userFlags = flags
                              }
                            , Cmd.none
                            )

                Err error ->
                    ( { key = key
                      , url = url
                      , contentCache = contentCache
                      , pageData = BuildError.errorToString error |> Err
                      , ariaNavigationAnnouncement = "Error"
                      , userFlags = flags
                      }
                    , Cmd.none
                    )

        Nothing ->
            ( { key = key
              , url = url
              , contentCache = contentCache
              , pageData = Err "TODO"
              , ariaNavigationAnnouncement = "Error"
              , userFlags = flags
              }
            , Cmd.none
            )


{-| -}
type Msg userMsg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | UserMsg userMsg
    | UpdateCache (Result Http.Error ( Url, ContentJson, ContentCache ))
    | UpdateCacheAndUrl Url (Result Http.Error ( Url, ContentJson, ContentCache ))
    | PageScrollComplete
    | HotReloadComplete ContentJson
    | ReloadCurrentPageData
    | NoOp


{-| -}
type alias Model userModel pageData sharedData =
    { key : Browser.Navigation.Key
    , url : Url
    , contentCache : ContentCache
    , ariaNavigationAnnouncement : String
    , pageData :
        Result
            String
            { userModel : userModel
            , pageData : pageData
            , sharedData : sharedData
            }
    , userFlags : Decode.Value
    }


{-| -}
update :
    ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Msg userMsg
    -> Model userModel pageData sharedData
    -> ( Model userModel pageData sharedData, Cmd (Msg userMsg) )
update config appMsg model =
    case appMsg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    let
                        navigatingToSamePage : Bool
                        navigatingToSamePage =
                            (url.path == model.url.path) && (url /= model.url)
                    in
                    if navigatingToSamePage then
                        -- this is a workaround for an issue with anchor fragment navigation
                        -- see https://github.com/elm/browser/issues/39
                        ( model, Browser.Navigation.load (Url.toString url) )

                    else
                        ( model
                        , Browser.Navigation.pushUrl model.key (Url.toString url)
                        )

                Browser.External href ->
                    ( model, Browser.Navigation.load href )

        UrlChanged url ->
            let
                navigatingToSamePage : Bool
                navigatingToSamePage =
                    (url.path == model.url.path) && (url /= model.url)

                urls : { currentUrl : Url, basePath : List String }
                urls =
                    { currentUrl = url
                    , basePath = config.basePath
                    }
            in
            if navigatingToSamePage then
                -- this saves a few CPU cycles, but also
                -- makes sure we don't send an UpdateCacheAndUrl
                -- which scrolls to the top after page changes.
                -- This is important because we may have just scrolled
                -- to a specific page location for an anchor link.
                model.pageData
                    |> Result.map
                        (\pageData ->
                            let
                                updatedPageData : Result String { userModel : userModel, sharedData : sharedData, pageData : pageData }
                                updatedPageData =
                                    Ok
                                        { userModel = userModel
                                        , sharedData = pageData.sharedData
                                        , pageData = pageData.pageData
                                        }

                                ( userModel, _ ) =
                                    config.update
                                        pageData.sharedData
                                        pageData.pageData
                                        (Just model.key)
                                        (config.onPageChange
                                            { protocol = model.url.protocol
                                            , host = model.url.host
                                            , port_ = model.url.port_
                                            , path = urlPathToPath config urls.currentUrl
                                            , query = url.query
                                            , fragment = url.fragment
                                            , metadata = config.urlToRoute url
                                            }
                                        )
                                        pageData.userModel
                            in
                            ( { model
                                | url = url
                                , pageData = updatedPageData
                              }
                            , Cmd.none
                              --Cmd.batch
                              --    [ userCmd |> Cmd.map UserMsg
                              --    , Task.perform (\_ -> PageScrollComplete) (Dom.setViewport 0 0)
                              --    ]
                            )
                        )
                    |> Result.withDefault ( model, Cmd.none )

            else
                ( model
                , model.contentCache
                    |> ContentCache.lazyLoad urls
                    |> Task.attempt (UpdateCacheAndUrl url)
                )

        ReloadCurrentPageData ->
            let
                urls : { currentUrl : Url, basePath : List String }
                urls =
                    { currentUrl = model.url
                    , basePath = config.basePath
                    }
            in
            ( model
            , model.contentCache
                |> ContentCache.eagerLoad urls
                |> Task.attempt (UpdateCacheAndUrl model.url)
            )

        UserMsg userMsg ->
            case model.pageData of
                Ok pageData ->
                    let
                        ( userModel, userCmd ) =
                            config.update pageData.sharedData pageData.pageData (Just model.key) userMsg pageData.userModel

                        updatedPageData : Result error { userModel : userModel, pageData : pageData, sharedData : sharedData }
                        updatedPageData =
                            Ok { pageData | userModel = userModel }
                    in
                    ( { model | pageData = updatedPageData }, userCmd |> Cmd.map UserMsg )

                Err _ ->
                    ( model, Cmd.none )

        UpdateCache cacheUpdateResult ->
            case cacheUpdateResult of
                -- TODO can there be race conditions here? Might need to set something in the model
                -- to keep track of the last url change
                Ok ( _, _, updatedCache ) ->
                    ( { model | contentCache = updatedCache }
                    , Cmd.none
                    )

                Err _ ->
                    -- TODO handle error
                    ( model, Cmd.none )

        UpdateCacheAndUrl url cacheUpdateResult ->
            case
                Result.map2 Tuple.pair (cacheUpdateResult |> Result.mapError (\_ -> "Http error")) model.pageData
            of
                -- TODO can there be race conditions here? Might need to set something in the model
                -- to keep track of the last url change
                Ok ( ( _, contentJson, updatedCache ), pageData ) ->
                    let
                        updatedPageData : Result String { userModel : userModel, sharedData : sharedData, pageData : pageData }
                        updatedPageData =
                            updatedPageStaticData
                                |> Result.map
                                    (\pageStaticData ->
                                        { userModel = userModel
                                        , sharedData = pageData.sharedData
                                        , pageData = pageStaticData
                                        }
                                    )

                        updatedPageStaticData : Result String pageData
                        updatedPageStaticData =
                            StaticHttpRequest.resolve ApplicationType.Browser
                                (config.data (config.urlToRoute url))
                                contentJson.staticData
                                |> Result.mapError
                                    (\error ->
                                        error
                                            |> StaticHttpRequest.toBuildError ""
                                            |> BuildError.errorToString
                                    )
                                |> Result.andThen
                                    (\pageResponse ->
                                        case pageResponse of
                                            PageServerResponse.RenderPage _ renderPagePageData ->
                                                Ok renderPagePageData

                                            PageServerResponse.ServerResponse _ ->
                                                Err "Unexpected ServerResponse - was expecting RenderPage response."
                                    )

                        ( userModel, userCmd ) =
                            config.update
                                pageData.sharedData
                                (updatedPageStaticData |> Result.withDefault pageData.pageData)
                                (Just model.key)
                                (config.onPageChange
                                    { protocol = model.url.protocol
                                    , host = model.url.host
                                    , port_ = model.url.port_
                                    , path = url |> urlPathToPath config
                                    , query = url.query
                                    , fragment = url.fragment
                                    , metadata = config.urlToRoute url
                                    }
                                )
                                pageData.userModel

                        updatedModel : Model userModel pageData sharedData
                        updatedModel =
                            { model
                                | url = url
                                , contentCache = updatedCache
                                , pageData = updatedPageData
                            }
                    in
                    ( { updatedModel
                        | ariaNavigationAnnouncement = mainView config updatedModel |> .title
                      }
                    , Cmd.batch
                        [ userCmd |> Cmd.map UserMsg
                        , Task.perform (\_ -> PageScrollComplete) (Dom.setViewport 0 0)
                        ]
                    )

                Err _ ->
                    {-
                       When there is an error loading the content.json, we are either
                       1) in the dev server, and should show the relevant DataSource error for the page
                          we're navigating to. This could be done more cleanly, but it's simplest to just
                          do a fresh page load and use the code path for presenting an error for a fresh page.
                       2) In a production app. That means we had a successful build, so there were no DataSource failures,
                          so the app must be stale (unless it's in some unexpected state from a bug). In the future,
                          it probably makes sense to include some sort of hash of the app version we are fetching, match
                          it with the current version that's running, and perform this logic when we see there is a mismatch.
                          But for now, if there is any error we do a full page load (not a single-page navigation), which
                          gives us a fresh version of the app to make sure things are in sync.

                    -}
                    ( model
                    , url
                        |> Url.toString
                        |> Browser.Navigation.load
                    )

        PageScrollComplete ->
            ( model, Cmd.none )

        HotReloadComplete contentJson ->
            let
                urls : { currentUrl : Url, basePath : List String }
                urls =
                    { currentUrl = model.url
                    , basePath = config.basePath
                    }

                pageDataResult : Result BuildError (PageServerResponse pageData)
                pageDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        (config.data (config.urlToRoute model.url))
                        contentJson.staticData
                        |> Result.mapError (StaticHttpRequest.toBuildError model.url.path)

                sharedDataResult : Result BuildError sharedData
                sharedDataResult =
                    StaticHttpRequest.resolve ApplicationType.Browser
                        config.sharedData
                        contentJson.staticData
                        |> Result.mapError (StaticHttpRequest.toBuildError model.url.path)

                from404ToNon404 : Bool
                from404ToNon404 =
                    not contentJson.is404
                        && was404

                was404 : Bool
                was404 =
                    ContentCache.is404 model.contentCache urls
            in
            case Result.map2 Tuple.pair sharedDataResult pageDataResult of
                Ok ( sharedData, pageData_ ) ->
                    case pageData_ of
                        PageServerResponse.RenderPage _ pageData ->
                            let
                                updateResult : Maybe ( userModel, Cmd userMsg )
                                updateResult =
                                    if from404ToNon404 then
                                        case model.pageData of
                                            Ok pageData2_ ->
                                                config.update
                                                    sharedData
                                                    pageData
                                                    (Just model.key)
                                                    (config.onPageChange
                                                        { protocol = model.url.protocol
                                                        , host = model.url.host
                                                        , port_ = model.url.port_
                                                        , path = model.url |> urlPathToPath config
                                                        , query = model.url.query
                                                        , fragment = model.url.fragment
                                                        , metadata = config.urlToRoute model.url
                                                        }
                                                    )
                                                    pageData2_.userModel
                                                    |> Just

                                            Err _ ->
                                                Nothing

                                    else
                                        Nothing
                            in
                            case updateResult of
                                Just ( userModel, userCmd ) ->
                                    ( { model
                                        | contentCache =
                                            ContentCache.init
                                                (Just
                                                    ( urls.currentUrl
                                                        |> config.urlToRoute
                                                        |> config.routeToPath
                                                    , contentJson
                                                    )
                                                )
                                        , pageData =
                                            Ok
                                                { pageData = pageData
                                                , sharedData = sharedData
                                                , userModel = userModel
                                                }
                                      }
                                    , Cmd.batch
                                        [ userCmd |> Cmd.map UserMsg
                                        ]
                                    )

                                Nothing ->
                                    let
                                        pagePath : Path
                                        pagePath =
                                            urlsToPagePath urls

                                        userFlags : Pages.Flags.Flags
                                        userFlags =
                                            model.userFlags
                                                |> Decode.decodeValue
                                                    (Decode.field "userFlags" Decode.value)
                                                |> Result.withDefault Json.Encode.null
                                                |> Pages.Flags.BrowserFlags

                                        ( userModel, userCmd ) =
                                            Just
                                                { path =
                                                    { path = pagePath
                                                    , query = model.url.query
                                                    , fragment = model.url.fragment
                                                    }
                                                , metadata = config.urlToRoute model.url
                                                , pageUrl =
                                                    Just
                                                        { protocol = model.url.protocol
                                                        , host = model.url.host
                                                        , port_ = model.url.port_
                                                        , path = pagePath
                                                        , query = model.url.query |> Maybe.map QueryParams.fromString
                                                        , fragment = model.url.fragment
                                                        }
                                                }
                                                |> config.init userFlags sharedData pageData (Just model.key)
                                    in
                                    ( { model
                                        | contentCache =
                                            ContentCache.init
                                                (Just
                                                    ( urls.currentUrl
                                                        |> config.urlToRoute
                                                        |> config.routeToPath
                                                    , contentJson
                                                    )
                                                )
                                        , pageData =
                                            model.pageData
                                                |> Result.map
                                                    (\previousPageData ->
                                                        { pageData = pageData
                                                        , sharedData = sharedData
                                                        , userModel = previousPageData.userModel
                                                        }
                                                    )
                                                |> Result.withDefault
                                                    { pageData = pageData
                                                    , sharedData = sharedData
                                                    , userModel = userModel
                                                    }
                                                |> Ok
                                      }
                                    , userCmd |> Cmd.map UserMsg
                                    )

                        PageServerResponse.ServerResponse _ ->
                            ( model, Cmd.none )

                Err _ ->
                    ( { model
                        | contentCache =
                            ContentCache.init
                                (Just
                                    ( urls.currentUrl
                                        |> config.urlToRoute
                                        |> config.routeToPath
                                    , contentJson
                                    )
                                )
                      }
                    , Cmd.none
                    )

        NoOp ->
            ( model, Cmd.none )


{-| -}
application :
    ProgramConfig userMsg userModel route staticData pageData sharedData
    -> Platform.Program Flags (Model userModel pageData sharedData) (Msg userMsg)
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
                    urls : { currentUrl : Url }
                    urls =
                        { currentUrl = model.url }
                in
                case model.pageData of
                    Ok pageData ->
                        Sub.batch
                            [ config.subscriptions (model.url |> config.urlToRoute)
                                (urls.currentUrl |> config.urlToRoute |> config.routeToPath |> Path.join)
                                pageData.userModel
                                |> Sub.map UserMsg
                            , config.fromJsPort
                                |> Sub.map
                                    (\decodeValue ->
                                        case decodeValue |> Decode.decodeValue (Decode.field "contentJson" contentJsonDecoder) of
                                            Ok contentJson ->
                                                HotReloadComplete contentJson

                                            Err _ ->
                                                -- TODO should be no message here
                                                ReloadCurrentPageData
                                    )
                            ]

                    Err _ ->
                        config.fromJsPort
                            |> Sub.map
                                (\decodeValue ->
                                    case decodeValue |> Decode.decodeValue (Decode.field "contentJson" contentJsonDecoder) of
                                        Ok contentJson ->
                                            HotReloadComplete contentJson

                                        Err _ ->
                                            -- TODO should be no message here
                                            ReloadCurrentPageData
                                )
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


urlPathToPath : ProgramConfig userMsg userModel route siteData pageData sharedData -> Url -> Path
urlPathToPath config urls =
    urls.path |> Path.fromString
