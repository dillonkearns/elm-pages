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
import Dict exposing (Dict)
import FormDecoder
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Json.Decode as Decode
import Json.Encode
import Pages.ContentCache as ContentCache
import Pages.Fetcher
import Pages.Flags
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.ResponseSketch as ResponseSketch exposing (ResponseSketch)
import Pages.Internal.String as String
import Pages.Msg
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttpRequest as StaticHttpRequest
import Pages.Transition
import Path exposing (Path)
import QueryParams
import Task
import Url exposing (Url)


type Transition
    = Loading Int Path
    | Submitting FormDecoder.FormData


{-| -}
type alias Program userModel userMsg pageData actionData sharedData errorPage =
    Platform.Program Flags (Model userModel pageData actionData sharedData) (Msg userMsg pageData actionData sharedData errorPage)


mainView :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Model userModel pageData actionData sharedData
    -> { title : String, body : Html (Pages.Msg.Msg userMsg) }
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

                        currentUrl : Url
                        currentUrl =
                            model.url
                    in
                    (config.view (model.inFlightFetchers |> Dict.values)
                        (model.transition |> Maybe.map Tuple.second)
                        { path = ContentCache.pathForUrl urls |> Path.join
                        , route = config.urlToRoute { currentUrl | path = model.currentPath }
                        }
                        Nothing
                        pageData.sharedData
                        pageData.pageData
                        pageData.actionData
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
    ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Model userModel pageData actionData sharedData
    -> Browser.Document (Msg userMsg pageData actionData sharedData errorPage)
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


type InitKind shared page actionData errorPage
    = OkPage shared page (Maybe actionData)
    | NotFound { reason : NotFoundReason, path : Path }


{-| -}
init :
    ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Flags
    -> Url
    -> Maybe Browser.Navigation.Key
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
init config flags url key =
    let
        pageDataResult : Result BuildError (InitKind sharedData pageData actionData errorPage)
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
                            Just (ResponseSketch.RenderPage _ _) ->
                                Nothing

                            Just (ResponseSketch.HotUpdate pageData shared actionData) ->
                                OkPage shared pageData actionData
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
        Ok (OkPage sharedData pageData actionData) ->
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
                        |> config.init userFlags sharedData pageData actionData key

                cmd : Effect userMsg pageData actionData sharedData userEffect errorPage
                cmd =
                    UserCmd userCmd

                initialModel : Model userModel pageData actionData sharedData
                initialModel =
                    { key = key
                    , url = url
                    , currentPath = url.path
                    , pageData =
                        Ok
                            { pageData = pageData
                            , sharedData = sharedData
                            , userModel = userModel
                            , actionData = actionData
                            }
                    , ariaNavigationAnnouncement = ""
                    , userFlags = flags
                    , notFound = Nothing
                    , transition = Nothing
                    , nextTransitionKey = 0
                    , inFlightFetchers = Dict.empty
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
              , currentPath = url.path
              , pageData = Err "Not found"
              , ariaNavigationAnnouncement = "Error" -- TODO use error page title for announcement?
              , userFlags = flags
              , notFound = Just info
              , transition = Nothing
              , nextTransitionKey = 0
              , inFlightFetchers = Dict.empty
              }
            , NoEffect
            )

        Err error ->
            ( { key = key
              , url = url
              , currentPath = url.path
              , pageData =
                    error
                        |> BuildError.errorToString
                        |> Err
              , ariaNavigationAnnouncement = "Error"
              , userFlags = flags
              , notFound = Nothing
              , transition = Nothing
              , nextTransitionKey = 0
              , inFlightFetchers = Dict.empty
              }
            , NoEffect
            )


{-| -}
type Msg userMsg pageData actionData sharedData errorPage
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | UserMsg (Pages.Msg.Msg userMsg)
    | UpdateCacheAndUrlNew Bool Url (Maybe userMsg) (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ))
    | FetcherComplete Int (Result Http.Error (Maybe userMsg))
    | FetcherStarted FormDecoder.FormData
    | PageScrollComplete
    | HotReloadCompleteNew Bytes
    | ProcessFetchResponse (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData )) (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)


{-| -}
type alias Model userModel pageData actionData sharedData =
    { key : Maybe Browser.Navigation.Key
    , url : Url
    , currentPath : String
    , ariaNavigationAnnouncement : String
    , pageData :
        Result
            String
            { userModel : userModel
            , pageData : pageData
            , sharedData : sharedData
            , actionData : Maybe actionData
            }
    , notFound : Maybe { reason : NotFoundReason, path : Path }
    , userFlags : Decode.Value
    , transition : Maybe ( Int, Pages.Transition.Transition )
    , nextTransitionKey : Int
    , inFlightFetchers : Dict Int Pages.Transition.FetcherState
    }


type Effect userMsg pageData actionData sharedData userEffect errorPage
    = ScrollToTop
    | NoEffect
    | BrowserLoadUrl String
    | BrowserPushUrl String
    | BrowserReplaceUrl String
    | FetchPageData Int (Maybe FormDecoder.FormData) Url (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)
    | Submit FormDecoder.FormData
    | SubmitFetcher FormDecoder.FormData
    | Batch (List (Effect userMsg pageData actionData sharedData userEffect errorPage))
    | UserCmd userEffect
    | CancelRequest Int


{-| -}
update :
    ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Msg userMsg pageData actionData sharedData errorPage
    -> Model userModel pageData actionData sharedData
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
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
                        , BrowserPushUrl url.path
                        )

                Browser.External href ->
                    ( model
                    , BrowserLoadUrl href
                    )

        UrlChanged url ->
            ( { model
                -- update the URL in case query params or fragment changed
                | url = url
              }
            , NoEffect
            )
                -- TODO is it reasonable to always re-fetch route data if you re-navigate to the current route? Might be a good
                -- parallel to the browser behavior
                |> startNewGetLoad url (UpdateCacheAndUrlNew False url Nothing)

        FetcherComplete fetcherId userMsgResult ->
            case userMsgResult of
                Ok userMsg ->
                    ( { model
                        | inFlightFetchers =
                            model.inFlightFetchers
                                |> Dict.update fetcherId
                                    (Maybe.map
                                        (\fetcherState ->
                                            { fetcherState | status = Pages.Transition.FetcherReloading }
                                        )
                                    )
                      }
                    , NoEffect
                    )
                        |> (case userMsg of
                                Just justUserMsg ->
                                    performUserMsg justUserMsg config

                                Nothing ->
                                    identity
                           )
                        |> startNewGetLoad (currentUrlWithPath model.url.path model) (UpdateCacheAndUrlNew False model.url Nothing)

                Err _ ->
                    -- TODO how to handle error?
                    ( model, NoEffect )
                        |> startNewGetLoad (currentUrlWithPath model.url.path model) (UpdateCacheAndUrlNew False model.url Nothing)

        ProcessFetchResponse response toMsg ->
            case response of
                Ok ( _, ResponseSketch.Redirect redirectTo ) ->
                    ( model, NoEffect )
                        |> startNewGetLoad (currentUrlWithPath redirectTo model) toMsg

                _ ->
                    update config (toMsg response) model

        UserMsg userMsg_ ->
            case userMsg_ of
                Pages.Msg.UserMsg userMsg ->
                    ( model, NoEffect )
                        |> performUserMsg userMsg config

                Pages.Msg.Submit fields ->
                    ( { model
                        | transition =
                            Just
                                ( -- TODO remove hardcoded number
                                  -1
                                , Pages.Transition.Submitting fields
                                )
                      }
                    , Submit fields
                    )

                Pages.Msg.SubmitFetcher fields ->
                    ( model
                    , SubmitFetcher fields
                    )

        UpdateCacheAndUrlNew fromLinkClick urlWithoutRedirectResolution maybeUserMsg updateResult ->
            -- TODO remove all fetchers that are in the state `FetcherReloading` here -- I think that's the right logic?
            case
                Result.map2 Tuple.pair
                    (updateResult
                        |> Result.mapError (\_ -> "Http error")
                    )
                    model.pageData
            of
                Ok ( ( newUrl, newData ), previousPageData ) ->
                    let
                        redirectPending : Bool
                        redirectPending =
                            newUrl /= urlWithoutRedirectResolution
                    in
                    if redirectPending then
                        ( model, BrowserReplaceUrl newUrl.path )

                    else
                        let
                            ( newPageData, newSharedData, newActionData ) =
                                case newData of
                                    ResponseSketch.RenderPage pageData actionData ->
                                        ( pageData, previousPageData.sharedData, actionData )

                                    ResponseSketch.HotUpdate pageData sharedData actionData ->
                                        ( pageData, sharedData, actionData )

                                    _ ->
                                        ( previousPageData.pageData, previousPageData.sharedData, previousPageData.actionData )

                            updatedPageData : { userModel : userModel, sharedData : sharedData, actionData : Maybe actionData, pageData : pageData }
                            updatedPageData =
                                { userModel = userModel
                                , sharedData = newSharedData
                                , pageData = newPageData
                                , actionData = newActionData
                                }

                            ( userModel, _ ) =
                                -- TODO if urlWithoutRedirectResolution is different from the url with redirect resolution, then
                                -- instead of calling update, call pushUrl (I think?)
                                -- TODO include user Cmd
                                config.update (model.inFlightFetchers |> Dict.values)
                                    (model.transition |> Maybe.map Tuple.second)
                                    newSharedData
                                    newPageData
                                    model.key
                                    (config.onPageChange
                                        { protocol = model.url.protocol
                                        , host = model.url.host
                                        , port_ = model.url.port_
                                        , path = urlPathToPath urlWithoutRedirectResolution
                                        , query = urlWithoutRedirectResolution.query
                                        , fragment = urlWithoutRedirectResolution.fragment
                                        , metadata = config.urlToRoute urlWithoutRedirectResolution
                                        }
                                    )
                                    previousPageData.userModel

                            updatedModel : Model userModel pageData actionData sharedData
                            updatedModel =
                                { model
                                    | url = newUrl
                                    , pageData = Ok updatedPageData
                                    , transition = Nothing
                                }
                                    |> clearLoadingFetchers

                            onActionMsg : Maybe userMsg
                            onActionMsg =
                                newActionData |> Maybe.andThen config.onActionData
                        in
                        ( { updatedModel
                            | ariaNavigationAnnouncement = mainView config updatedModel |> .title
                            , currentPath = newUrl.path
                          }
                        , ScrollToTop
                        )
                            |> (case maybeUserMsg of
                                    Just userMsg ->
                                        withUserMsg config userMsg

                                    Nothing ->
                                        identity
                               )
                            |> (case onActionMsg of
                                    Just actionMsg ->
                                        withUserMsg config actionMsg

                                    Nothing ->
                                        identity
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
                            newThing : Maybe (ResponseSketch pageData actionData sharedData)
                            newThing =
                                -- TODO if ErrorPage, call ErrorPage.init to get appropriate Model?
                                pageDataBytes
                                    |> Bytes.Decode.decode config.decodeResponse
                        in
                        case newThing of
                            Just (ResponseSketch.RenderPage newPageData newActionData) ->
                                ( { model
                                    | pageData =
                                        Ok
                                            { userModel = pageData.userModel
                                            , sharedData = pageData.sharedData
                                            , pageData = newPageData
                                            , actionData = newActionData
                                            }
                                    , notFound = Nothing
                                  }
                                , NoEffect
                                )

                            Just (ResponseSketch.HotUpdate newPageData newSharedData newActionData) ->
                                ( { model
                                    | pageData =
                                        Ok
                                            { userModel = pageData.userModel
                                            , sharedData = newSharedData
                                            , pageData = newPageData
                                            , actionData = newActionData
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

        FetcherStarted fetcherData ->
            -- TODO
            ( { model
                | nextTransitionKey = model.nextTransitionKey + 1
                , inFlightFetchers =
                    model.inFlightFetchers
                        |> Dict.insert model.nextTransitionKey
                            { payload = fetcherData, status = Pages.Transition.FetcherSubmitting }
              }
            , NoEffect
            )


performUserMsg :
    userMsg
    -> ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
performUserMsg userMsg config ( model, effect ) =
    case model.pageData of
        Ok pageData ->
            let
                ( userModel, userCmd ) =
                    config.update (model.inFlightFetchers |> Dict.values) (model.transition |> Maybe.map Tuple.second) pageData.sharedData pageData.pageData model.key userMsg pageData.userModel

                updatedPageData : Result error { userModel : userModel, pageData : pageData, actionData : Maybe actionData, sharedData : sharedData }
                updatedPageData =
                    Ok { pageData | userModel = userModel }
            in
            ( { model | pageData = updatedPageData }
            , Batch [ effect, UserCmd userCmd ]
            )

        Err _ ->
            ( model, effect )


perform : ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage -> Model userModel pageData actionData sharedData -> Effect userMsg pageData actionData sharedData userEffect errorPage -> Cmd (Msg userMsg pageData actionData sharedData errorPage)
perform config model effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        NoEffect ->
            Cmd.none

        Batch effects ->
            effects
                |> List.map (perform config model)
                |> Cmd.batch

        ScrollToTop ->
            Task.perform (\_ -> PageScrollComplete) (Dom.setViewport 0 0)

        BrowserLoadUrl url ->
            Browser.Navigation.load url

        BrowserPushUrl url ->
            model.key
                |> Maybe.map
                    (\key ->
                        Browser.Navigation.pushUrl key url
                    )
                |> Maybe.withDefault Cmd.none

        BrowserReplaceUrl url ->
            model.key
                |> Maybe.map
                    (\key ->
                        Browser.Navigation.replaceUrl key url
                    )
                |> Maybe.withDefault Cmd.none

        FetchPageData transitionKey maybeRequestInfo url toMsg ->
            fetchRouteData transitionKey toMsg config url maybeRequestInfo

        Submit fields ->
            let
                urlToSubmitTo : Url
                urlToSubmitTo =
                    -- TODO add optional path parameter to Submit variant to allow submitting to other routes
                    model.url
            in
            Cmd.batch
                [ model.key
                    |> Maybe.map (\key -> Browser.Navigation.pushUrl key (appendFormQueryParams fields))
                    |> Maybe.withDefault Cmd.none
                , fetchRouteData -1 (UpdateCacheAndUrlNew False model.url Nothing) config urlToSubmitTo (Just fields)
                ]

        SubmitFetcher formData ->
            startFetcher2 formData model

        UserCmd cmd ->
            case model.key of
                Just key ->
                    let
                        prepare :
                            (Result Http.Error Url -> userMsg)
                            -> Result Http.Error ( Url, ResponseSketch pageData actionData sharedData )
                            -> Msg userMsg pageData actionData sharedData errorPage
                        prepare toMsg info =
                            UpdateCacheAndUrlNew False model.url (info |> Result.map Tuple.first |> toMsg |> Just) info
                    in
                    cmd
                        |> config.perform
                            { fetchRouteData =
                                \fetchInfo ->
                                    fetchRouteData -1
                                        (prepare fetchInfo.toMsg)
                                        config
                                        (urlFromAction model.url fetchInfo.data)
                                        fetchInfo.data

                            ---- TODO map the Msg with the wrapper type (like in the PR branch)
                            , submit =
                                \fetchInfo ->
                                    fetchRouteData -1 (prepare fetchInfo.toMsg) config (fetchInfo.values.action |> Url.fromString |> Maybe.withDefault model.url) (Just fetchInfo.values)
                            , runFetcher =
                                \(Pages.Fetcher.Fetcher options) ->
                                    startFetcher options model
                            , fromPageMsg = Pages.Msg.UserMsg >> UserMsg
                            , key = key
                            }

                Nothing ->
                    Cmd.none

        CancelRequest transitionKey ->
            Http.cancel (String.fromInt transitionKey)


startFetcher : { fields : List ( String, String ), url : Maybe String, decoder : Result error Bytes -> value, headers : List ( String, String ) } -> Model userModel pageData actionData sharedData -> Cmd (Msg value pageData actionData sharedData errorPage)
startFetcher options model =
    let
        encodedBody : String
        encodedBody =
            FormDecoder.encodeFormData
                { fields = options.fields

                -- TODO remove hardcoding
                , action = ""

                -- TODO remove hardcoding
                , method = FormDecoder.Post
                }

        formData =
            { -- TODO remove hardcoding
              method = FormDecoder.Get

            -- TODO pass FormData directly
            , action = options.url |> Maybe.withDefault model.url.path
            , fields = options.fields
            }
    in
    -- TODO make sure that `actionData` isn't updated in Model for fetchers
    Cmd.batch
        [ Task.succeed (FetcherStarted formData) |> Task.perform identity
        , Http.request
            { expect =
                Http.expectBytesResponse (FetcherComplete model.nextTransitionKey)
                    (\bytes ->
                        case bytes of
                            Http.GoodStatus_ metadata bytesBody ->
                                options.decoder (Ok bytesBody)
                                    |> Just
                                    |> Ok

                            _ ->
                                Debug.todo ""
                    )
            , tracker = Nothing
            , body = Http.stringBody "application/x-www-form-urlencoded" encodedBody
            , headers = options.headers |> List.map (\( name, value ) -> Http.header name value)
            , url = options.url |> Maybe.withDefault (Path.join [ model.url.path, "content.dat" ] |> Path.toAbsolute)
            , method = "POST"
            , timeout = Nothing
            }
        ]


startFetcher2 : FormDecoder.FormData -> Model userModel pageData actionData sharedData -> Cmd (Msg userMsg pageData actionData sharedData errorPage)
startFetcher2 formData model =
    let
        encodedBody : String
        encodedBody =
            FormDecoder.encodeFormData formData
    in
    -- TODO make sure that `actionData` isn't updated in Model for fetchers
    Cmd.batch
        [ Task.succeed (FetcherStarted formData) |> Task.perform identity
        , Http.request
            { expect =
                Http.expectBytesResponse (FetcherComplete model.nextTransitionKey)
                    (\bytes ->
                        case bytes of
                            Http.GoodStatus_ metadata bytesBody ->
                                -- TODO maybe have an optional way to pass the bytes through?
                                Ok Nothing

                            _ ->
                                -- TODO where should errors go in application state? Should there be an onError where you can receive application-managed error events that are owned by
                                -- the Platform Model/Msg's?
                                Debug.todo ""
                    )
            , tracker = Nothing

            -- TODO use formData.method to do either query params or POST body
            , body = Http.stringBody "application/x-www-form-urlencoded" encodedBody
            , headers = []

            -- TODO use formData.method to do either query params or POST body
            , url = formData.action |> Url.fromString |> Maybe.map (\{ path } -> Path.join [ path, "content.dat" ] |> Path.toAbsolute) |> Maybe.withDefault "/"
            , method = formData.method |> FormDecoder.methodToString
            , timeout = Nothing
            }
        ]


appendFormQueryParams : FormDecoder.FormData -> String
appendFormQueryParams fields =
    (fields.action
        |> Url.fromString
        |> Maybe.map .path
        |> Maybe.withDefault "/"
    )
        ++ (case fields.method of
                FormDecoder.Get ->
                    "?" ++ FormDecoder.encodeFormData fields

                FormDecoder.Post ->
                    ""
           )


urlFromAction : Url -> Maybe FormDecoder.FormData -> Url
urlFromAction currentUrl fetchInfo =
    fetchInfo |> Maybe.map .action |> Maybe.andThen Url.fromString |> Maybe.withDefault currentUrl


{-| -}
application :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Platform.Program Flags (Model userModel pageData actionData sharedData) (Msg userMsg pageData actionData sharedData errorPage)
application config =
    Browser.application
        { init =
            \flags url key ->
                let
                    ( model, effect ) =
                        init config flags url (Just key)
                in
                ( model
                , effect |> perform config model
                )
        , view = view config
        , update =
            \msg model ->
                update config msg model |> Tuple.mapSecond (perform config model)
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
                                |> Sub.map (Pages.Msg.UserMsg >> UserMsg)
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


withUserMsg :
    ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> userMsg
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
withUserMsg config userMsg ( model, effect ) =
    case model.pageData of
        Ok pageData ->
            let
                ( userModel, userCmd ) =
                    config.update (model.inFlightFetchers |> Dict.values) (model.transition |> Maybe.map Tuple.second) pageData.sharedData pageData.pageData model.key userMsg pageData.userModel

                updatedPageData : Result error { userModel : userModel, pageData : pageData, actionData : Maybe actionData, sharedData : sharedData }
                updatedPageData =
                    Ok { pageData | userModel = userModel }
            in
            ( { model | pageData = updatedPageData }
            , Batch
                [ effect
                , UserCmd userCmd
                ]
            )

        Err _ ->
            ( model, effect )


urlPathToPath : Url -> Path
urlPathToPath urls =
    urls.path |> Path.fromString


fetchRouteData :
    Int
    -> (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)
    -> ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Url
    -> Maybe FormDecoder.FormData
    -> Cmd (Msg userMsg pageData actionData sharedData errorPage)
fetchRouteData transitionKey toMsg config url details =
    {-
       TODO:
       - [X] `toMsg` needs a parameter for the callback Msg so it can pass it on if there is a Redirect response
       - [X] Handle ResponseSketch.Redirect in `update`
       - [ ] Set transition state when loading
       - [ ] Set transition state when submitting
       - [ ] Should transition state for redirect after submit be the same as a regular load transition state?
       - [ ] Expose transition state (in Shared?)
       - [ ] Abort stale transitions
       - [ ] Increment cancel key counter in Model on new transitions

    -}
    let
        formMethod : FormDecoder.Method
        formMethod =
            details
                |> Maybe.map .method
                |> Maybe.withDefault FormDecoder.Get

        urlEncodedFields : Maybe String
        urlEncodedFields =
            details
                |> Maybe.map FormDecoder.encodeFormData
    in
    Http.request
        { method = details |> Maybe.map (.method >> FormDecoder.methodToString) |> Maybe.withDefault "GET"
        , headers = []
        , url =
            "/"
                ++ (url.path
                        |> chopForwardSlashes
                        |> String.split "/"
                        |> List.filter ((/=) "")
                        |> (\l -> l ++ [ "content.dat" ])
                        |> String.join "/"
                   )
                ++ (case formMethod of
                        FormDecoder.Post ->
                            "/"

                        FormDecoder.Get ->
                            details
                                |> Maybe.map FormDecoder.encodeFormData
                                |> Maybe.map (\encoded -> "?" ++ encoded)
                                |> Maybe.withDefault ""
                   )
                ++ (case formMethod of
                        -- TODO extract this to something unit testable
                        -- TODO make states mutually exclusive for submissions and direct URL requests (shouldn't be possible to append two query param strings)
                        FormDecoder.Post ->
                            ""

                        FormDecoder.Get ->
                            url.query
                                |> Maybe.map (\encoded -> "?" ++ encoded)
                                |> Maybe.withDefault ""
                   )
        , body =
            case formMethod of
                FormDecoder.Post ->
                    urlEncodedFields
                        |> Maybe.map (\encoded -> Http.stringBody "application/x-www-form-urlencoded" encoded)
                        |> Maybe.withDefault Http.emptyBody

                _ ->
                    Http.emptyBody
        , expect =
            Http.expectBytesResponse (\response -> ProcessFetchResponse response toMsg)
                (\response ->
                    case response of
                        Http.BadUrl_ url_ ->
                            Err (Http.BadUrl url_)

                        Http.Timeout_ ->
                            Err Http.Timeout

                        Http.NetworkError_ ->
                            Err Http.NetworkError

                        Http.BadStatus_ metadata body ->
                            body
                                |> Bytes.Decode.decode config.decodeResponse
                                |> Result.fromMaybe "Decoding error"
                                |> Result.mapError Http.BadBody
                                |> Result.map (\okResponse -> ( url, okResponse ))

                        Http.GoodStatus_ _ body ->
                            body
                                |> Bytes.Decode.decode config.decodeResponse
                                |> Result.fromMaybe "Decoding error"
                                |> Result.mapError Http.BadBody
                                |> Result.map (\okResponse -> ( url, okResponse ))
                )
        , timeout = Nothing
        , tracker = Just (String.fromInt transitionKey)
        }


chopForwardSlashes : String -> String
chopForwardSlashes =
    chopStart "/" >> chopEnd "/"


chopStart : String -> String -> String
chopStart needle string =
    if String.startsWith needle string then
        chopStart needle (String.dropLeft (String.length needle) string)

    else
        string


chopEnd : String -> String -> String
chopEnd needle string =
    if String.endsWith needle string then
        chopEnd needle (String.dropRight (String.length needle) string)

    else
        string


startNewGetLoad :
    Url
    -> (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
startNewGetLoad urlToGet toMsg ( model, effect ) =
    let
        cancelIfStale : Effect userMsg pageData actionData sharedData userEffect errorPage
        cancelIfStale =
            case model.transition of
                Just ( transitionKey, Pages.Transition.Loading path loadingKind ) ->
                    CancelRequest transitionKey

                _ ->
                    NoEffect
    in
    ( { model
        | nextTransitionKey = model.nextTransitionKey + 1
        , transition =
            ( model.nextTransitionKey
            , Pages.Transition.Loading
                (urlToGet.path |> Path.fromString)
                Pages.Transition.Load
            )
                |> Just
      }
    , Batch
        [ FetchPageData
            model.nextTransitionKey
            Nothing
            urlToGet
            toMsg
        , cancelIfStale
        , effect
        ]
    )


clearLoadingFetchers : Model userModel pageData actionData sharedData -> Model userModel pageData actionData sharedData
clearLoadingFetchers model =
    { model
        | inFlightFetchers =
            model.inFlightFetchers
                |> Dict.filter (\_ fetcherState -> fetcherState.status /= Pages.Transition.FetcherReloading)
    }


currentUrlWithPath : String -> Model userModel pageData actionData sharedData -> Url
currentUrlWithPath path { url } =
    { url | path = path }
