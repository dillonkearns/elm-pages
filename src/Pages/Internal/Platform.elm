module Pages.Internal.Platform exposing
    ( Flags, Model, Msg(..), Program, application, init, update
    , Effect(..), RequestInfo, view
    )

{-| Exposed for internal use only (used in generated code).

@docs Flags, Model, Msg, Program, application, init, update

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
import Pages.Internal.Effect
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
type alias Program userModel userMsg pageData sharedData errorPage =
    Platform.Program Flags (Model userModel pageData sharedData) (Msg userMsg pageData sharedData errorPage)


mainView :
    ProgramConfig userMsg userModel route pageData sharedData effect (Msg userMsg pageData sharedData errorPage) errorPage
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
    ProgramConfig userMsg userModel route pageData sharedData effect (Msg userMsg pageData sharedData errorPage) errorPage
    -> Model userModel pageData sharedData
    -> Browser.Document (Msg userMsg pageData sharedData errorPage)
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


type InitKind shared page errorPage
    = OkPage shared page
    | NotFound { reason : NotFoundReason, path : Path }


{-| -}
init :
    ProgramConfig userMsg userModel route pageData sharedData userEffect (Msg userMsg pageData sharedData errorPage) errorPage
    -> Flags
    -> Url
    -> Maybe Browser.Navigation.Key
    -> ( Model userModel pageData sharedData, Effect userMsg pageData sharedData userEffect errorPage )
init config flags url key =
    let
        pageDataResult : Result BuildError (InitKind sharedData pageData errorPage)
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
                                OkPage shared pageData
                                    |> Just

                            Just (ResponseSketch.NotFound notFound) ->
                                NotFound notFound
                                    |> Just

                            _ ->
                                Nothing
                    )
                |> Result.fromMaybe
                    (StaticHttpRequest.DecoderError "Bytes decode error"
                        |> StaticHttpRequest.toBuildError url.path
                    )
    in
    case pageDataResult of
        Ok (OkPage sharedData pageData) ->
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
                        |> config.init userFlags sharedData pageData key

                cmd : Effect userMsg pageData sharedData userEffect errorPage
                cmd =
                    UserCmd userCmd

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

        Ok (NotFound info) ->
            ( { key = key
              , url = url
              , pageData = Err "Not found"
              , ariaNavigationAnnouncement = "Error" -- TODO use error page title for announcement?
              , userFlags = flags
              , notFound = Just info
              }
            , NoEffect
            )

        Err error ->
            ( { key = key
              , url = url
              , pageData =
                    error
                        |> BuildError.errorToString
                        |> Err
              , ariaNavigationAnnouncement = "Error"
              , userFlags = flags
              , notFound = Nothing
              }
            , NoEffect
            )


{-| -}
type Msg userMsg pageData sharedData errorPage
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | UserMsg userMsg
    | UpdateCacheAndUrlNew Bool Url (Result Http.Error ( Url, ResponseSketch pageData sharedData ))
    | PageScrollComplete
    | HotReloadCompleteNew Bytes
    | ReloadCurrentPageData RequestInfo


{-| -}
type alias Model userModel pageData sharedData =
    { key : Maybe Browser.Navigation.Key
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


fromUserEffect : Pages.Internal.Effect.Effect userMsg userEffect -> Effect userMsg pageData sharedData userEffect errorPage
fromUserEffect effect =
    case effect of
        Pages.Internal.Effect.ScrollToTop ->
            ScrollToTop

        Pages.Internal.Effect.NoEffect ->
            NoEffect

        Pages.Internal.Effect.BrowserLoadUrl string ->
            BrowserLoadUrl string

        Pages.Internal.Effect.BrowserPushUrl string ->
            BrowserPushUrl string

        Pages.Internal.Effect.FetchPageData requestInfo url _ ->
            FetchPageData requestInfo url (Debug.todo "")

        --(Maybe RequestInfo) Url (Result Http.Error ( Url, ResponseSketch pageData sharedData ) -> Msg userMsg pageData sharedData errorPage)
        Pages.Internal.Effect.Batch list ->
            list
                |> List.map fromUserEffect
                |> Batch

        Pages.Internal.Effect.UserEffect userEffect ->
            UserCmd userEffect


type Effect userMsg pageData sharedData userEffect errorPage
    = ScrollToTop
    | NoEffect
    | BrowserLoadUrl String
    | BrowserPushUrl String
    | FetchPageData (Maybe RequestInfo) Url (Result Http.Error ( Url, ResponseSketch pageData sharedData ) -> Msg userMsg pageData sharedData errorPage)
    | Batch (List (Effect userMsg pageData sharedData userEffect errorPage))
    | UserCmd userEffect


{-| -}
update :
    ProgramConfig userMsg userModel route pageData sharedData userEffect (Msg userMsg pageData sharedData errorPage) errorPage
    -> Msg userMsg pageData sharedData errorPage
    -> Model userModel pageData sharedData
    -> ( Model userModel pageData sharedData, Effect userMsg pageData sharedData userEffect errorPage )
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
                        ( model
                        , BrowserLoadUrl (Url.toString url)
                        )

                    else
                        ( model
                        , FetchPageData Nothing url (UpdateCacheAndUrlNew True url)
                        )

                Browser.External href ->
                    ( model
                    , BrowserLoadUrl href
                    )

        UrlChanged url ->
            let
                navigatingToSamePage : Bool
                navigatingToSamePage =
                    url.path == model.url.path
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
                                        model.key
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
                            , NoEffect
                            )
                        )
                    |> Result.withDefault ( model, NoEffect )

            else
                ( model
                , FetchPageData Nothing url (UpdateCacheAndUrlNew False url)
                )

        ReloadCurrentPageData requestInfo ->
            ( model
            , FetchPageData (Just requestInfo) model.url (UpdateCacheAndUrlNew False model.url)
            )

        UserMsg userMsg ->
            case model.pageData of
                Ok pageData ->
                    let
                        ( userModel, userCmd ) =
                            config.update pageData.sharedData pageData.pageData model.key userMsg pageData.userModel

                        updatedPageData : Result error { userModel : userModel, pageData : pageData, sharedData : sharedData }
                        updatedPageData =
                            Ok { pageData | userModel = userModel }
                    in
                    ( { model | pageData = updatedPageData }
                    , UserCmd userCmd
                    )

                Err _ ->
                    ( model, NoEffect )

        UpdateCacheAndUrlNew fromLinkClick urlWithoutRedirectResolution updateResult ->
            case
                Result.map2 Tuple.pair
                    (updateResult
                        |> Result.mapError (\_ -> "Http error")
                    )
                    model.pageData
            of
                Ok ( ( newUrl, newData ), previousPageData ) ->
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
                            -- TODO call update on new Model for ErrorPage
                            config.update
                                newSharedData
                                newPageData
                                model.key
                                (config.onPageChange
                                    { protocol = model.url.protocol
                                    , host = model.url.host
                                    , port_ = model.url.port_
                                    , path = newUrl |> urlPathToPath
                                    , query = newUrl.query
                                    , fragment = newUrl.fragment
                                    , metadata = config.urlToRoute newUrl
                                    }
                                )
                                previousPageData.userModel

                        updatedModel : Model userModel pageData sharedData
                        updatedModel =
                            { model
                                | url = newUrl
                                , pageData = Ok updatedPageData
                            }
                    in
                    ( { updatedModel
                        | ariaNavigationAnnouncement = mainView config updatedModel |> .title
                      }
                    , Batch
                        [ UserCmd userCmd
                        , ScrollToTop
                        , if fromLinkClick || urlWithoutRedirectResolution.path /= newUrl.path then
                            BrowserPushUrl newUrl.path

                          else
                            NoEffect
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
                    , urlWithoutRedirectResolution
                        |> Url.toString
                        |> BrowserLoadUrl
                    )

        PageScrollComplete ->
            ( model, NoEffect )

        HotReloadCompleteNew pageDataBytes ->
            model.pageData
                |> Result.map
                    (\pageData ->
                        let
                            newThing : Maybe (ResponseSketch pageData sharedData)
                            newThing =
                                -- TODO if ErrorPage, call ErrorPage.init to get appropriate Model?
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
                                , NoEffect
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
                                , NoEffect
                                )

                            Just (ResponseSketch.NotFound info) ->
                                ( { model | notFound = Just info }, NoEffect )

                            _ ->
                                ( model, NoEffect )
                    )
                |> Result.withDefault ( model, NoEffect )


perform : ProgramConfig userMsg userModel route pageData sharedData userEffect (Msg userMsg pageData sharedData errorPage) errorPage -> Maybe Browser.Navigation.Key -> Effect userMsg pageData sharedData userEffect errorPage -> Cmd (Msg userMsg pageData sharedData errorPage)
perform config maybeKey effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        NoEffect ->
            Cmd.none

        Batch effects ->
            effects
                |> List.map (perform config maybeKey)
                |> Cmd.batch

        ScrollToTop ->
            Task.perform (\_ -> PageScrollComplete) (Dom.setViewport 0 0)

        BrowserLoadUrl url ->
            Browser.Navigation.load url

        BrowserPushUrl url ->
            maybeKey
                |> Maybe.map
                    (\key ->
                        Browser.Navigation.pushUrl key url
                    )
                |> Maybe.withDefault Cmd.none

        FetchPageData maybeRequestInfo url toMsg ->
            config.fetchPageData url maybeRequestInfo
                |> Task.attempt toMsg

        UserCmd cmd ->
            case maybeKey of
                Just key ->
                    cmd
                        |> config.perform UserMsg key
                        -- TODO it should never be Maybe if it gets here... would be nice to remove
                        |> Maybe.withDefault Cmd.none

                Nothing ->
                    Cmd.none


{-| -}
application :
    ProgramConfig userMsg userModel route pageData sharedData effect (Msg userMsg pageData sharedData errorPage) errorPage
    -> Platform.Program Flags (Model userModel pageData sharedData) (Msg userMsg pageData sharedData errorPage)
application config =
    Browser.application
        { init =
            \flags url key ->
                init config flags url (Just key)
                    |> Tuple.mapSecond (perform config (Just key))
        , view = view config
        , update =
            \msg model ->
                update config msg model |> Tuple.mapSecond (perform config model.key)
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
                                    (\value ->
                                        case value |> Decode.decodeValue fromJsPortDecoder of
                                            Ok requestInfo ->
                                                ReloadCurrentPageData requestInfo

                                            Err _ ->
                                                PageScrollComplete
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


type alias RequestInfo =
    { contentType : String
    , body : String
    }


fromJsPortDecoder : Decode.Decoder RequestInfo
fromJsPortDecoder =
    Decode.field "tag" Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "Reload" ->
                        Decode.field "data"
                            (Decode.map2 RequestInfo
                                (Decode.field "content-type" Decode.string)
                                (Decode.field "body" Decode.string)
                            )

                    _ ->
                        Decode.fail <| "Unexpected tag " ++ tag
            )


urlPathToPath : Url -> Path
urlPathToPath urls =
    urls.path |> Path.fromString
