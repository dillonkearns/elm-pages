module Pages.Internal.Platform exposing (Flags, Model, Msg, Program, application)

{-| Exposed for internal use only (used in generated code).

@docs Flags, Model, Msg, Program, application

-}

import AriaLiveAnnouncer
import Base64
import Browser
import Browser.Dom as Dom
import Browser.Navigation
import BuildError exposing (BuildError)
import Bytes exposing (Bytes)
import Bytes.Decode
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Json.Decode as Decode
import Json.Encode
import Pages.ContentCache as ContentCache
import Pages.Flags
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.ResponseSketch as ResponseSketch exposing (ResponseSketch)
import Pages.Internal.String as String
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttpRequest as StaticHttpRequest
import Path exposing (Path)
import QueryParams
import Task
import Url exposing (Url)


{-| -}
type alias Program userModel userMsg pageData sharedData =
    Platform.Program Flags (Model userModel pageData sharedData) (Msg userMsg pageData sharedData)


mainView :
    ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Model userModel pageData sharedData
    -> { title : String, body : Html userMsg }
mainView config model =
    case model.notFound of
        Just info ->
            Pages.Internal.NotFoundReason.document config.pathPatterns info

        Nothing ->
            case model.pageData of
                Ok pageData ->
                    let
                        urls : { currentUrl : Url, basePath : List String }
                        urls =
                            { currentUrl = model.url
                            , basePath = config.basePath
                            }
                    in
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
    -> Browser.Document (Msg userMsg pageData sharedData)
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
    -> ( Model userModel pageData sharedData, Cmd (Msg userMsg pageData sharedData) )
init config flags url key =
    let
        pageDataResult : Result BuildError ( pageData, sharedData )
        pageDataResult =
            flags
                |> Decode.decodeValue (Decode.field "pageDataBase64" Decode.string)
                |> Result.toMaybe
                |> Maybe.andThen Base64.toBytes
                |> Maybe.andThen
                    (\justBytes ->
                        case
                            Bytes.Decode.decode
                                -- TODO should this use byteDecodePageData, or should it be decoding ResponseSketch data?
                                config.decodeResponse
                                justBytes
                        of
                            Just (ResponseSketch.RenderPage _) ->
                                Nothing

                            Just (ResponseSketch.HotUpdate pageData shared) ->
                                Just ( pageData, shared )

                            _ ->
                                Nothing
                    )
                |> Result.fromMaybe
                    (StaticHttpRequest.DecoderError "Bytes decode error"
                        |> StaticHttpRequest.toBuildError url.path
                    )
    in
    case pageDataResult of
        Ok ( pageData, sharedData ) ->
            let
                urls : { currentUrl : Url, basePath : List String }
                urls =
                    { currentUrl = url
                    , basePath = config.basePath
                    }

                pagePath : Path
                pagePath =
                    urlsToPagePath urls

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

                cmd : Cmd (Msg userMsg pageData sharedData)
                cmd =
                    [ userCmd
                        |> Cmd.map UserMsg
                        |> Just
                    ]
                        |> List.filterMap identity
                        |> Cmd.batch

                initialModel : Model userModel pageData sharedData
                initialModel =
                    { key = key
                    , url = url
                    , pageData =
                        Ok
                            { pageData = pageData
                            , sharedData = sharedData
                            , userModel = userModel
                            }
                    , ariaNavigationAnnouncement = ""
                    , userFlags = flags
                    , notFound = Nothing
                    }
            in
            ( { initialModel
                | ariaNavigationAnnouncement = mainView config initialModel |> .title
              }
            , cmd
            )

        Err error ->
            ( { key = key
              , url = url
              , pageData = BuildError.errorToString error |> Err
              , ariaNavigationAnnouncement = "Error"
              , userFlags = flags
              , notFound = Nothing
              }
            , Cmd.none
            )


{-| -}
type Msg userMsg pageData sharedData
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | UserMsg userMsg
    | UpdateCacheAndUrlNew Url (Result Http.Error (ResponseSketch pageData sharedData))
    | PageScrollComplete
    | HotReloadCompleteNew Bytes
    | ReloadCurrentPageData


{-| -}
type alias Model userModel pageData sharedData =
    { key : Browser.Navigation.Key
    , url : Url
    , ariaNavigationAnnouncement : String
    , pageData :
        Result
            String
            { userModel : userModel
            , pageData : pageData
            , sharedData : sharedData
            }
    , notFound : Maybe { reason : NotFoundReason, path : Path }
    , userFlags : Decode.Value
    }


{-| -}
update :
    ProgramConfig userMsg userModel route siteData pageData sharedData
    -> Msg userMsg pageData sharedData
    -> Model userModel pageData sharedData
    -> ( Model userModel pageData sharedData, Cmd (Msg userMsg pageData sharedData) )
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
                                urls : { currentUrl : Url, basePath : List String }
                                urls =
                                    { currentUrl = url
                                    , basePath = config.basePath
                                    }

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
                                            , path = urlPathToPath urls.currentUrl
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
                , config.fetchPageData url
                    |> Task.attempt (UpdateCacheAndUrlNew url)
                )

        ReloadCurrentPageData ->
            ( model
            , Cmd.none
              -- @@@ TODO re-implement with Bytes decoding
              --model.contentCache
              --    |> ContentCache.eagerLoad urls
              --    |> Task.attempt (UpdateCacheAndUrl model.url)
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

        UpdateCacheAndUrlNew url cacheUpdateResult ->
            case Result.map2 Tuple.pair (cacheUpdateResult |> Result.mapError (\_ -> "Http error")) model.pageData of
                Ok ( newData, previousPageData ) ->
                    let
                        ( newPageData, newSharedData ) =
                            case newData of
                                ResponseSketch.RenderPage pageData ->
                                    ( pageData, previousPageData.sharedData )

                                ResponseSketch.HotUpdate pageData sharedData ->
                                    ( pageData, sharedData )

                                _ ->
                                    ( previousPageData.pageData, previousPageData.sharedData )

                        updatedPageData : { userModel : userModel, sharedData : sharedData, pageData : pageData }
                        updatedPageData =
                            { userModel = userModel
                            , sharedData = newSharedData
                            , pageData = newPageData
                            }

                        ( userModel, userCmd ) =
                            config.update
                                newSharedData
                                newPageData
                                (Just model.key)
                                (config.onPageChange
                                    { protocol = model.url.protocol
                                    , host = model.url.host
                                    , port_ = model.url.port_
                                    , path = url |> urlPathToPath
                                    , query = url.query
                                    , fragment = url.fragment
                                    , metadata = config.urlToRoute url
                                    }
                                )
                                previousPageData.userModel

                        updatedModel : Model userModel pageData sharedData
                        updatedModel =
                            { model
                                | url = url
                                , pageData = Ok updatedPageData
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
                       When there is an error loading the content.dat, we are either
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

        HotReloadCompleteNew pageDataBytes ->
            model.pageData
                |> Result.map
                    (\pageData ->
                        let
                            newThing : Maybe (ResponseSketch pageData sharedData)
                            newThing =
                                pageDataBytes
                                    |> Bytes.Decode.decode config.decodeResponse
                        in
                        case newThing of
                            Just (ResponseSketch.RenderPage newPageData) ->
                                ( { model
                                    | pageData =
                                        Ok
                                            { userModel = pageData.userModel
                                            , sharedData = pageData.sharedData
                                            , pageData = newPageData
                                            }
                                    , notFound = Nothing
                                  }
                                , Cmd.none
                                )

                            Just (ResponseSketch.HotUpdate newPageData newSharedData) ->
                                ( { model
                                    | pageData =
                                        Ok
                                            { userModel = pageData.userModel
                                            , sharedData = newSharedData
                                            , pageData = newPageData
                                            }
                                    , notFound = Nothing
                                  }
                                , Cmd.none
                                )

                            Just (ResponseSketch.NotFound info) ->
                                ( { model | notFound = Just info }, Cmd.none )

                            _ ->
                                ( model, Cmd.none )
                    )
                |> Result.withDefault ( model, Cmd.none )


{-| -}
application :
    ProgramConfig userMsg userModel route staticData pageData sharedData
    -> Platform.Program Flags (Model userModel pageData sharedData) (Msg userMsg pageData sharedData)
application config =
    Browser.application
        { init =
            \flags url key ->
                init config flags url key
        , view = view config
        , update = update config
        , subscriptions =
            \model ->
                case model.pageData of
                    Ok pageData ->
                        let
                            urls : { currentUrl : Url }
                            urls =
                                { currentUrl = model.url }
                        in
                        Sub.batch
                            [ config.subscriptions (model.url |> config.urlToRoute)
                                (urls.currentUrl |> config.urlToRoute |> config.routeToPath |> Path.join)
                                pageData.userModel
                                |> Sub.map UserMsg
                            , config.fromJsPort
                                |> Sub.map
                                    (\_ ->
                                        -- TODO should be no message here
                                        ReloadCurrentPageData
                                    )
                            , config.hotReloadData
                                |> Sub.map HotReloadCompleteNew
                            ]

                    Err _ ->
                        config.hotReloadData
                            |> Sub.map HotReloadCompleteNew
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


urlPathToPath : Url -> Path
urlPathToPath urls =
    urls.path |> Path.fromString
