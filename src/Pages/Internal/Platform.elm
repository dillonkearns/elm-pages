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


type alias Program userModel userMsg pageData sharedData =
    Platform.Program Flags (Model userModel pageData sharedData) (Msg userMsg)


mainView :
    ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model userModel pageData sharedData
    -> { title : String, body : Html userMsg }
mainView config model =
    let
        urls =
            { currentUrl = model.url
            , baseUrl = model.baseUrl
            }
    in
    if ContentCache.is404 model.contentCache urls then
        { title = "Page not found"
        , body =
            Html.div [] [ Html.text "Page not found." ]
        }

    else
        case model.pageData of
            Ok pageData ->
                (config.view
                    { path = ContentCache.pathForUrl urls |> PagePath.build
                    , frontmatter = config.urlToRoute model.url
                    }
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


urlToPagePath : Url -> Url -> PagePath
urlToPagePath url baseUrl =
    url.path
        |> String.dropLeft (String.length baseUrl.path)
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")
        |> PagePath.build


urlsToPagePath :
    { currentUrl : Url
    , baseUrl : Url
    }
    -> PagePath
urlsToPagePath urls =
    urls.currentUrl.path
        |> String.dropLeft (String.length urls.baseUrl.path)
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")
        |> PagePath.build


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
    , is404 : Bool
    }


contentJsonDecoder : Decode.Decoder ContentJson
contentJsonDecoder =
    Decode.map2 ContentJson
        (Decode.field "staticData" RequestsAndPending.decoder)
        (Decode.field "is404" Decode.bool)


init :
    ProgramConfig userMsg userModel route staticData pageData sharedData
    -> Flags
    -> Url
    -> Browser.Navigation.Key
    -> ( Model userModel pageData sharedData, Cmd (Msg userMsg) )
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
                pageDataResult : Result BuildError pageData
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

                pagePath =
                    urlsToPagePath urls
            in
            case Result.map2 Tuple.pair sharedDataResult pageDataResult of
                Ok ( sharedData, pageData ) ->
                    let
                        ( userModel, userCmd ) =
                            Just
                                { path =
                                    { path = pagePath
                                    , query = url.query
                                    , fragment = url.fragment
                                    }
                                , metadata = config.urlToRoute url
                                }
                                |> config.init sharedData pageData (Just key)

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
                                { pageData = pageData
                                , sharedData = sharedData
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
    | NoOp


type alias Model userModel pageData sharedData =
    { key : Browser.Navigation.Key
    , url : Url
    , baseUrl : Url
    , contentCache : ContentCache
    , pageData :
        Result
            String
            { userModel : userModel
            , pageData : pageData
            , sharedData : sharedData
            }
    }


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
                            config.update pageData.sharedData pageData.pageData (Just model.key) userMsg pageData.userModel

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
                        updatedPageData =
                            updatedPageStaticData
                                |> Result.map
                                    (\pageStaticData ->
                                        { userModel = userModel
                                        , sharedData = pageData.sharedData
                                        , pageData = pageStaticData
                                        }
                                    )

                        updatedPageStaticData =
                            StaticHttpRequest.resolve ApplicationType.Browser
                                (config.data (config.urlToRoute url))
                                contentJson.staticData
                                |> Result.mapError (\_ -> "Http error")

                        ( userModel, userCmd ) =
                            config.update
                                pageData.sharedData
                                (updatedPageStaticData |> Result.withDefault pageData.pageData)
                                (Just model.key)
                                (config.onPageChange
                                    { path = urlToPagePath url model.baseUrl
                                    , query = url.query
                                    , fragment = url.fragment
                                    , metadata = config.urlToRoute url
                                    }
                                )
                                pageData.userModel
                    in
                    ( { model
                        | url = url
                        , contentCache = updatedCache
                        , pageData = updatedPageData
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

                pageDataResult : Result BuildError pageData
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

                from404ToNon404 =
                    not contentJson.is404
                        && was404

                was404 =
                    ContentCache.is404 model.contentCache urls
            in
            case Result.map2 Tuple.pair sharedDataResult pageDataResult of
                Ok ( sharedData, pageData ) ->
                    let
                        updateResult =
                            if from404ToNon404 then
                                case model.pageData of
                                    Ok pageData_ ->
                                        config.update
                                            sharedData
                                            pageData
                                            (Just model.key)
                                            (config.onPageChange
                                                { path = urlToPagePath model.url model.baseUrl
                                                , query = model.url.query
                                                , fragment = model.url.fragment
                                                , metadata = config.urlToRoute model.url
                                                }
                                            )
                                            pageData_.userModel
                                            |> Just

                                    Err error ->
                                        Nothing

                            else
                                Nothing
                    in
                    case updateResult of
                        Just ( userModel, userCmd ) ->
                            ( { model
                                | contentCache = ContentCache.init (Just ( urls, contentJson ))
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
                            ( { model
                                | contentCache =
                                    ContentCache.init (Just ( urls, contentJson ))
                                , pageData =
                                    model.pageData
                                        |> Result.map
                                            (\previousPageData ->
                                                { pageData = pageData
                                                , sharedData = sharedData
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

        NoOp ->
            ( model, Cmd.none )


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
                    urls =
                        { currentUrl = model.url, baseUrl = model.baseUrl }

                    pagePath =
                        urlsToPagePath urls
                in
                case model.pageData of
                    Ok pageData ->
                        Sub.batch
                            [ config.subscriptions (model.url |> config.urlToRoute) pagePath pageData.userModel
                                |> Sub.map UserMsg
                            , config.fromJsPort
                                |> Sub.map
                                    (\decodeValue ->
                                        case decodeValue |> Decode.decodeValue (Decode.field "contentJson" contentJsonDecoder) of
                                            Ok contentJson ->
                                                HotReloadComplete contentJson

                                            Err _ ->
                                                -- TODO should be no message here
                                                NoOp
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
                                            NoOp
                                )
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
