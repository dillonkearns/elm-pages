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
import FormDecoder
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


type Payload
    = Payload


type Transition
    = Loading Int Path
    | Submitting Path Payload


{-| -}
type alias Program userModel userMsg pageData actionData sharedData errorPage =
    Platform.Program Flags (Model userModel pageData actionData sharedData) (Msg userMsg pageData actionData sharedData errorPage)


mainView :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Model userModel pageData actionData sharedData
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
              , transition = Nothing
              , nextTransitionKey = 0
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
              , transition = Nothing
              , nextTransitionKey = 0
              }
            , NoEffect
            )


{-| -}
type Msg userMsg pageData actionData sharedData errorPage
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | UserMsg userMsg
    | UpdateCacheAndUrlNew Bool Url (Maybe userMsg) (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ))
    | FetcherComplete (Result Http.Error userMsg)
    | PageScrollComplete
    | HotReloadCompleteNew Bytes
    | ProcessFetchResponse (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData )) (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)


{-| -}
type alias Model userModel pageData actionData sharedData =
    { key : Maybe Browser.Navigation.Key
    , url : Url
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
    , transition : Maybe Transition
    , nextTransitionKey : Int
    }


type Effect userMsg pageData actionData sharedData userEffect errorPage
    = ScrollToTop
    | NoEffect
    | BrowserLoadUrl String
    | BrowserPushUrl String
    | FetchPageData Int (Maybe RequestInfo) Url (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)
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
                        ( { model
                            | transition =
                                url.path
                                    |> Path.fromString
                                    |> Loading model.nextTransitionKey
                                    |> Just
                            , nextTransitionKey = model.nextTransitionKey + 1
                          }
                        , FetchPageData model.nextTransitionKey Nothing url (UpdateCacheAndUrlNew True url Nothing)
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

                                updatedPageData : Result String { userModel : userModel, sharedData : sharedData, pageData : pageData, actionData : Maybe actionData }
                                updatedPageData =
                                    Ok
                                        { userModel = userModel
                                        , sharedData = pageData.sharedData
                                        , pageData = pageData.pageData
                                        , actionData = pageData.actionData
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
                , NoEffect
                )
                    |> startNewGetLoad url.path (UpdateCacheAndUrlNew False url Nothing)

        FetcherComplete userMsgResult ->
            case userMsgResult of
                Ok userMsg ->
                    ( model, NoEffect )
                        |> performUserMsg userMsg config
                        |> startNewGetLoad model.url.path (UpdateCacheAndUrlNew False model.url Nothing)

                Err _ ->
                    -- TODO how to handle error?
                    ( model, NoEffect )
                        |> startNewGetLoad model.url.path (UpdateCacheAndUrlNew False model.url Nothing)

        ProcessFetchResponse response toMsg ->
            case response of
                Ok ( _, ResponseSketch.Redirect redirectTo ) ->
                    ( model, NoEffect )
                        |> startNewGetLoad redirectTo toMsg

                _ ->
                    update config (toMsg response) model

        UserMsg userMsg ->
            ( model, NoEffect )
                |> performUserMsg userMsg config

        UpdateCacheAndUrlNew fromLinkClick urlWithoutRedirectResolution maybeUserMsg updateResult ->
            case
                Result.map2 Tuple.pair
                    (updateResult
                        |> Result.mapError (\_ -> "Http error")
                    )
                    model.pageData
            of
                Ok ( ( newUrl, newData ), previousPageData ) ->
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
                            { userModel = previousPageData.userModel
                            , sharedData = newSharedData
                            , pageData = newPageData
                            , actionData = newActionData
                            }

                        updatedModel : Model userModel pageData actionData sharedData
                        updatedModel =
                            { model
                                | url = newUrl
                                , pageData = Ok updatedPageData
                            }
                    in
                    case maybeUserMsg of
                        Just userMsg ->
                            ( { updatedModel
                                | ariaNavigationAnnouncement = mainView config updatedModel |> .title
                              }
                            , Batch
                                [ ScrollToTop
                                , if fromLinkClick || urlWithoutRedirectResolution.path /= newUrl.path then
                                    BrowserPushUrl newUrl.path

                                  else
                                    NoEffect
                                ]
                            )
                                |> withUserMsg config userMsg

                        Nothing ->
                            ( { updatedModel
                                | ariaNavigationAnnouncement = mainView config updatedModel |> .title
                              }
                            , Batch
                                [ ScrollToTop
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
                    config.update pageData.sharedData pageData.pageData model.key userMsg pageData.userModel

                updatedPageData : Result error { userModel : userModel, pageData : pageData, actionData : Maybe actionData, sharedData : sharedData }
                updatedPageData =
                    Ok { pageData | userModel = userModel }
            in
            ( { model | pageData = updatedPageData }
            , Batch [ effect, UserCmd userCmd ]
            )

        Err _ ->
            ( model, effect )


perform : ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage -> Url -> Maybe Browser.Navigation.Key -> Effect userMsg pageData actionData sharedData userEffect errorPage -> Cmd (Msg userMsg pageData actionData sharedData errorPage)
perform config currentUrl maybeKey effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        NoEffect ->
            Cmd.none

        Batch effects ->
            effects
                |> List.map (perform config currentUrl maybeKey)
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

        FetchPageData transitionKey maybeRequestInfo url toMsg ->
            fetchRouteData transitionKey toMsg config url maybeRequestInfo

        UserCmd cmd ->
            case maybeKey of
                Just key ->
                    let
                        prepare :
                            (Result Http.Error Url -> userMsg)
                            -> Result Http.Error ( Url, ResponseSketch pageData actionData sharedData )
                            -> Msg userMsg pageData actionData sharedData errorPage
                        prepare toMsg info =
                            UpdateCacheAndUrlNew True currentUrl (info |> Result.map Tuple.first |> toMsg |> Just) info
                    in
                    cmd
                        |> config.perform
                            { fetchRouteData =
                                \fetchInfo ->
                                    case fetchInfo.path of
                                        Just path ->
                                            fetchRouteData -1 (prepare fetchInfo.toMsg) config { currentUrl | path = path } fetchInfo.body

                                        Nothing ->
                                            fetchRouteData -1 (prepare fetchInfo.toMsg) config currentUrl fetchInfo.body

                            -- TODO map the Msg with the wrapper type (like in the PR branch)
                            , submit =
                                \fetchInfo ->
                                    let
                                        urlToSubmitTo : Url
                                        urlToSubmitTo =
                                            case fetchInfo.path of
                                                Just path ->
                                                    { currentUrl | path = path }

                                                Nothing ->
                                                    currentUrl
                                    in
                                    fetchRouteData -1 (prepare fetchInfo.toMsg) config urlToSubmitTo (Just (FormDecoder.encodeFormData fetchInfo.values))
                            , runFetcher =
                                \options ->
                                    let
                                        { contentType, body } =
                                            FormDecoder.encodeFormData options.fields
                                    in
                                    -- TODO make sure that `actionData` isn't updated in Model for fetchers
                                    Http.request
                                        { expect =
                                            Http.expectBytesResponse FetcherComplete
                                                (\bytes ->
                                                    case bytes of
                                                        Http.GoodStatus_ metadata bytesBody ->
                                                            options.decoder (Ok bytesBody)
                                                                |> Ok

                                                        _ ->
                                                            Debug.todo ""
                                                )
                                        , tracker = Nothing
                                        , body = Http.stringBody contentType body
                                        , headers = options.headers |> List.map (\( name, value ) -> Http.header name value)
                                        , url = options.url |> Maybe.withDefault (Path.join [ currentUrl.path, "content.dat" ] |> Path.toAbsolute)
                                        , method = "POST"
                                        , timeout = Nothing
                                        }
                            , fromPageMsg = UserMsg
                            , key = key
                            }

                Nothing ->
                    Cmd.none

        CancelRequest transitionKey ->
            Http.cancel (String.fromInt transitionKey)


{-| -}
application :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Platform.Program Flags (Model userModel pageData actionData sharedData) (Msg userMsg pageData actionData sharedData errorPage)
application config =
    Browser.application
        { init =
            \flags url key ->
                init config flags url (Just key)
                    |> Tuple.mapSecond (perform config url (Just key))
        , view = view config
        , update =
            \msg model ->
                update config msg model |> Tuple.mapSecond (perform config model.url model.key)
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
                    config.update pageData.sharedData pageData.pageData model.key userMsg pageData.userModel

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
    -> Maybe { contentType : String, body : String }
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
    Http.request
        { method = details |> Maybe.map (\_ -> "POST") |> Maybe.withDefault "GET"
        , headers = []
        , url =
            url.path
                |> chopForwardSlashes
                |> String.split "/"
                |> List.filter ((/=) "")
                |> (\l -> l ++ [ "content.dat" ])
                |> String.join "/"
                |> String.append "/"
        , body = details |> Maybe.map (\justDetails -> Http.stringBody justDetails.contentType justDetails.body) |> Maybe.withDefault Http.emptyBody
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
    String
    -> (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
startNewGetLoad pathToGet toMsg ( model, effect ) =
    let
        currentUrl : Url
        currentUrl =
            model.url

        cancelIfStale : Effect userMsg pageData actionData sharedData userEffect errorPage
        cancelIfStale =
            case model.transition of
                Just (Loading transitionKey path) ->
                    CancelRequest transitionKey

                _ ->
                    NoEffect
    in
    ( { model
        | nextTransitionKey = model.nextTransitionKey + 1
        , transition =
            pathToGet
                |> Path.fromString
                |> Loading model.nextTransitionKey
                |> Just
      }
    , Batch
        [ FetchPageData
            model.nextTransitionKey
            Nothing
            { currentUrl | path = pathToGet }
            toMsg
        , cancelIfStale
        , effect
        ]
    )
