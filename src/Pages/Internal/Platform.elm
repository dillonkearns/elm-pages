module Pages.Internal.Platform exposing
    ( Flags, Model, Msg(..), Program, application, init, update
    , Effect(..), RequestInfo, view
    )

{-| Exposed for internal use only (used in generated code).

@docs Flags, Model, Msg, Program, application, init, update

@docs Effect, RequestInfo, view

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
import Form
import Form.FormData exposing (FormData, Method(..))
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Json.Decode as Decode
import Json.Encode
import Pages.ContentCache as ContentCache
import Pages.Fetcher
import Pages.Flags
import Pages.Internal.Msg
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.ResponseSketch as ResponseSketch exposing (ResponseSketch)
import Pages.Internal.String as String
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.StaticHttpRequest as StaticHttpRequest
import Pages.Transition
import PagesMsg exposing (PagesMsg)
import Path exposing (Path)
import QueryParams
import Task
import Time
import Url exposing (Url)


{-| -}
type alias Program userModel userMsg pageData actionData sharedData errorPage =
    Platform.Program Flags (Model userModel pageData actionData sharedData) (Msg userMsg pageData actionData sharedData errorPage)


mainView :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Model userModel pageData actionData sharedData
    -> { title : String, body : List (Html (PagesMsg userMsg)) }
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
                    (config.view model.pageFormState
                        (model.inFlightFetchers |> toFetcherState)
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
                        [ Html.div [] [ Html.text error ] ]
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


{-| -}
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
        , AriaLiveAnnouncer.view model.ariaNavigationAnnouncement
        ]
            ++ List.map (Html.map UserMsg) body
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
                                , query = url.query |> Maybe.map QueryParams.fromString |> Maybe.withDefault Dict.empty
                                , fragment = url.fragment
                                }
                        }
                        |> config.init userFlags sharedData pageData actionData

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
                    , pageFormState = Dict.empty
                    , pendingRedirect = False
                    , pendingData = Nothing
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
              , ariaNavigationAnnouncement = "Page Not Found" -- TODO use error page title for announcement?
              , userFlags = flags
              , notFound = Just info
              , transition = Nothing
              , nextTransitionKey = 0
              , inFlightFetchers = Dict.empty
              , pageFormState = Dict.empty
              , pendingRedirect = False
              , pendingData = Nothing
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
              , pageFormState = Dict.empty
              , pendingRedirect = False
              , pendingData = Nothing
              }
            , NoEffect
            )


{-| -}
type Msg userMsg pageData actionData sharedData errorPage
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
      -- TODO rename to PagesMsg
    | UserMsg (PagesMsg userMsg)
      --| SetField { formId : String, name : String, value : String }
    | FormMsg (Form.Msg (Msg userMsg pageData actionData sharedData errorPage))
    | UpdateCacheAndUrlNew Bool Url (Maybe userMsg) (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ))
    | FetcherComplete Bool String Int (Result Http.Error ( Maybe userMsg, ActionDataOrRedirect actionData ))
    | FetcherStarted String Int FormData Time.Posix
    | PageScrollComplete
    | HotReloadCompleteNew Bytes
    | ProcessFetchResponse Int (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData )) (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)


type ActionDataOrRedirect action
    = ActionResponse (Maybe action)
    | RedirectResponse String


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
    , inFlightFetchers : Dict String ( Int, Pages.Transition.FetcherState actionData )
    , pageFormState : Form.Model
    , pendingRedirect : Bool
    , pendingData : Maybe ( pageData, sharedData, Maybe actionData )
    }


{-| -}
type Effect userMsg pageData actionData sharedData userEffect errorPage
    = ScrollToTop
    | NoEffect
    | BrowserLoadUrl String
    | BrowserPushUrl String
    | BrowserReplaceUrl String
    | FetchPageData Int (Maybe FormData) Url (Result Http.Error ( Url, ResponseSketch pageData actionData sharedData ) -> Msg userMsg pageData actionData sharedData errorPage)
    | Submit FormData
    | SubmitFetcher String Int FormData
    | Batch (List (Effect userMsg pageData actionData sharedData userEffect errorPage))
    | UserCmd userEffect
    | CancelRequest Int
    | RunCmd (Cmd (Msg userMsg pageData actionData sharedData errorPage))


{-| -}
update :
    ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Msg userMsg pageData actionData sharedData errorPage
    -> Model userModel pageData actionData sharedData
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
update config appMsg model =
    case appMsg of
        FormMsg formMsg ->
            let
                -- TODO trigger formCmd
                ( newModel, formCmd ) =
                    Form.update formMsg model.pageFormState
            in
            ( { model
                | pageFormState = newModel
              }
            , RunCmd formCmd
            )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    let
                        navigatingToSamePage : Bool
                        navigatingToSamePage =
                            url.path == model.url.path
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
            case model.pendingData of
                Just ( newPageData, newSharedData, newActionData ) ->
                    loadDataAndUpdateUrl
                        ( newPageData, newSharedData, newActionData )
                        Nothing
                        url
                        url
                        False
                        config
                        model

                Nothing ->
                    if model.url.path == url.path && model.url.query == url.query then
                        ( { model
                            | -- update the URL in case query params or fragment changed
                              url = url
                          }
                        , NoEffect
                        )

                    else
                        ( model
                        , NoEffect
                        )
                            -- TODO is it reasonable to always re-fetch route data if you re-navigate to the current route? Might be a good
                            -- parallel to the browser behavior
                            |> startNewGetLoad url (UpdateCacheAndUrlNew True url Nothing)

        FetcherComplete _ fetcherKey _ userMsgResult ->
            case userMsgResult of
                Ok ( userMsg, actionOrRedirect ) ->
                    case actionOrRedirect of
                        ActionResponse maybeFetcherDoneActionData ->
                            ( { model
                                | inFlightFetchers =
                                    model.inFlightFetchers
                                        |> Dict.update fetcherKey
                                            (Maybe.map
                                                (\( transitionId, fetcherState ) ->
                                                    ( transitionId
                                                    , { fetcherState
                                                        | status =
                                                            maybeFetcherDoneActionData
                                                                |> Maybe.map Pages.Transition.FetcherReloading
                                                                -- TODO remove this bad default, FetcherSubmitting is incorrect
                                                                |> Maybe.withDefault Pages.Transition.FetcherSubmitting
                                                      }
                                                    )
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

                        RedirectResponse redirectTo ->
                            ( { model
                                | inFlightFetchers =
                                    model.inFlightFetchers
                                        |> Dict.remove fetcherKey
                                , pendingRedirect = True
                              }
                            , NoEffect
                            )
                                |> startNewGetLoad (currentUrlWithPath redirectTo model) (UpdateCacheAndUrlNew False model.url Nothing)

                Err _ ->
                    -- TODO how to handle error?
                    ( model, NoEffect )
                        |> startNewGetLoad (currentUrlWithPath model.url.path model) (UpdateCacheAndUrlNew False model.url Nothing)

        ProcessFetchResponse transitionId response toMsg ->
            case response of
                Ok ( _, ResponseSketch.Redirect redirectTo ) ->
                    ( model, NoEffect )
                        |> startNewGetLoad (currentUrlWithPath redirectTo model) toMsg

                _ ->
                    update config (toMsg response) (clearLoadingFetchersAfterDataLoad transitionId model)

        UserMsg userMsg_ ->
            case userMsg_ of
                Pages.Internal.Msg.UserMsg userMsg ->
                    ( model, NoEffect )
                        |> performUserMsg userMsg config

                Pages.Internal.Msg.Submit fields ->
                    let
                        payload : { fields : List ( String, String ), method : Method, action : String, id : Maybe String }
                        payload =
                            { fields = fields.fields
                            , method = Post -- TODO
                            , action = fields.action
                            , id = Just fields.id
                            }
                    in
                    if fields.valid then
                        if fields.useFetcher then
                            ( { model | nextTransitionKey = model.nextTransitionKey + 1 }
                            , SubmitFetcher fields.id model.nextTransitionKey payload
                            )
                                |> (case fields.msg of
                                        Just justUserMsg ->
                                            performUserMsg justUserMsg config

                                        Nothing ->
                                            identity
                                   )

                        else
                            ( { model
                                -- TODO should I setSubmitAttempted here, too?
                                | transition =
                                    Just
                                        ( -- TODO remove hardcoded number
                                          -1
                                        , Pages.Transition.Submitting payload
                                        )
                              }
                            , Submit payload
                            )
                                |> (case fields.msg of
                                        Just justUserMsg ->
                                            performUserMsg justUserMsg config

                                        Nothing ->
                                            identity
                                   )

                    else
                        ( model, NoEffect )

                Pages.Internal.Msg.FormMsg formMsg ->
                    -- TODO when init is called for a new page, also need to clear out client-side `pageFormState`
                    let
                        ( formModel, formCmd ) =
                            Form.update formMsg model.pageFormState
                    in
                    ( { model | pageFormState = formModel }
                    , RunCmd (Cmd.map UserMsg formCmd)
                    )

                Pages.Internal.Msg.NoOp ->
                    ( model, NoEffect )

        UpdateCacheAndUrlNew scrollToTopWhenDone urlWithoutRedirectResolution maybeUserMsg updateResult ->
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
                        ( { model
                            | pendingRedirect = True
                            , pendingData =
                                case newData of
                                    ResponseSketch.RenderPage pageData actionData ->
                                        Just ( pageData, previousPageData.sharedData, actionData )

                                    ResponseSketch.HotUpdate pageData sharedData actionData ->
                                        Just ( pageData, sharedData, actionData )

                                    _ ->
                                        Nothing
                          }
                        , BrowserReplaceUrl newUrl.path
                        )

                    else
                        let
                            stayingOnSamePath : Bool
                            stayingOnSamePath =
                                newUrl.path == model.url.path

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

                            ( userModel, userEffect ) =
                                -- TODO if urlWithoutRedirectResolution is different from the url with redirect resolution, then
                                -- instead of calling update, call pushUrl (I think?)
                                -- TODO include user Cmd
                                if stayingOnSamePath then
                                    ( previousPageData.userModel, NoEffect )

                                else
                                    config.update model.pageFormState
                                        (model.inFlightFetchers |> toFetcherState)
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
                                        |> Tuple.mapSecond UserCmd

                            updatedModel : Model userModel pageData actionData sharedData
                            updatedModel =
                                -- TODO should these be the same (no if)?
                                if model.pendingRedirect || redirectPending then
                                    { model
                                        | url = newUrl
                                        , pageData = Ok updatedPageData
                                        , transition = Nothing
                                        , pendingRedirect = False
                                        , pageFormState = Dict.empty
                                    }

                                else
                                    { model
                                        | url = newUrl
                                        , pageData = Ok updatedPageData
                                        , pendingRedirect = False
                                        , transition = Nothing
                                    }

                            onActionMsg : Maybe userMsg
                            onActionMsg =
                                newActionData |> Maybe.andThen config.onActionData
                        in
                        ( { updatedModel
                            | ariaNavigationAnnouncement = mainView config updatedModel |> .title
                            , currentPath = newUrl.path
                          }
                        , if not stayingOnSamePath && scrollToTopWhenDone then
                            Batch
                                [ ScrollToTop
                                , userEffect
                                ]

                          else
                            userEffect
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
                       1) in the dev server, and should show the relevant BackendTask error for the page
                          we're navigating to. This could be done more cleanly, but it's simplest to just
                          do a fresh page load and use the code path for presenting an error for a fresh page.
                       2) In a production app. That means we had a successful build, so there were no BackendTask failures,
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
                |> Result.withDefault
                    (let
                        pageDataResult : Maybe (InitKind sharedData pageData actionData errorPage)
                        pageDataResult =
                            case Bytes.Decode.decode config.decodeResponse pageDataBytes of
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
                     in
                     case pageDataResult of
                        Just (OkPage sharedData pageData actionData) ->
                            let
                                urls : { currentUrl : Url, basePath : List String }
                                urls =
                                    { currentUrl = model.url
                                    , basePath = config.basePath
                                    }

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
                                                , query = model.url.query |> Maybe.map QueryParams.fromString |> Maybe.withDefault Dict.empty
                                                , fragment = model.url.fragment
                                                }
                                        }
                                        |> config.init userFlags sharedData pageData actionData

                                cmd : Effect userMsg pageData actionData sharedData userEffect errorPage
                                cmd =
                                    UserCmd userCmd
                            in
                            ( { model
                                | pageData =
                                    Ok
                                        { userModel = userModel
                                        , sharedData = sharedData
                                        , pageData = pageData
                                        , actionData = actionData
                                        }
                                , notFound = Nothing
                              }
                            , cmd
                            )

                        _ ->
                            ( model, NoEffect )
                    )

        FetcherStarted fetcherKey transitionId fetcherData initiatedAt ->
            ( { model
                | inFlightFetchers =
                    model.inFlightFetchers
                        |> Dict.insert fetcherKey
                            ( transitionId
                            , { payload = fetcherData
                              , status = Pages.Transition.FetcherSubmitting
                              , initiatedAt = initiatedAt
                              }
                            )
              }
            , NoEffect
            )


toFetcherState : Dict String ( Int, Pages.Transition.FetcherState actionData ) -> Dict String (Pages.Transition.FetcherState actionData)
toFetcherState inFlightFetchers =
    inFlightFetchers
        |> Dict.map (\_ ( _, fetcherState ) -> fetcherState)


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
                    config.update model.pageFormState (model.inFlightFetchers |> toFetcherState) (model.transition |> Maybe.map Tuple.second) pageData.sharedData pageData.pageData model.key userMsg pageData.userModel

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

        RunCmd cmd ->
            cmd

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
            if fields.method == Get then
                model.key
                    |> Maybe.map (\key -> Browser.Navigation.pushUrl key (appendFormQueryParams fields))
                    |> Maybe.withDefault Cmd.none

            else
                let
                    urlToSubmitTo : Url
                    urlToSubmitTo =
                        -- TODO add optional path parameter to Submit variant to allow submitting to other routes
                        model.url
                in
                fetchRouteData -1 (UpdateCacheAndUrlNew False model.url Nothing) config urlToSubmitTo (Just fields)

        SubmitFetcher fetcherKey transitionId formData ->
            startFetcher2 config False fetcherKey transitionId formData model

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
                                    fetchRouteData
                                        -1
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
                                    -- TODO need to get the fetcherId here
                                    -- TODO need to increment and pass in the transitionId
                                    startFetcher "TODO" -1 options model
                            , fromPageMsg = Pages.Internal.Msg.UserMsg >> UserMsg
                            , key = key
                            , setField =
                                \info ->
                                    --Task.succeed (SetField info) |> Task.perform identity
                                    -- TODO
                                    Cmd.none
                            }

                Nothing ->
                    Cmd.none

        CancelRequest transitionKey ->
            Http.cancel (String.fromInt transitionKey)


startFetcher : String -> Int -> { fields : List ( String, String ), url : Maybe String, decoder : Result error Bytes -> value, headers : List ( String, String ) } -> Model userModel pageData actionData sharedData -> Cmd (Msg value pageData actionData sharedData errorPage)
startFetcher fetcherKey transitionId options model =
    let
        encodedBody : String
        encodedBody =
            encodeFormData options.fields

        formData : { method : Method, action : String, fields : List ( String, String ), id : Maybe String }
        formData =
            { -- TODO remove hardcoding
              method = Get

            -- TODO pass FormData directly
            , action = options.url |> Maybe.withDefault model.url.path
            , fields = options.fields
            , id = Nothing
            }
    in
    -- TODO make sure that `actionData` isn't updated in Model for fetchers
    Cmd.batch
        [ cancelStaleFetchers model
        , Time.now |> Task.map (FetcherStarted fetcherKey transitionId formData) |> Task.perform identity
        , Http.request
            { expect =
                Http.expectBytesResponse (FetcherComplete False fetcherKey model.nextTransitionKey)
                    (\bytes ->
                        case bytes of
                            Http.GoodStatus_ _ bytesBody ->
                                ( options.decoder (Ok bytesBody)
                                    |> Just
                                , ActionResponse Nothing
                                )
                                    |> Ok

                            Http.BadUrl_ string ->
                                Err <| Http.BadUrl string

                            Http.Timeout_ ->
                                Err <| Http.Timeout

                            Http.NetworkError_ ->
                                Err <| Http.NetworkError

                            Http.BadStatus_ metadata _ ->
                                Err <| Http.BadStatus metadata.statusCode
                    )
            , tracker = Nothing
            , body = Http.stringBody "application/x-www-form-urlencoded" encodedBody
            , headers = options.headers |> List.map (\( name, value ) -> Http.header name value)
            , url = options.url |> Maybe.withDefault (Path.join [ model.url.path, "content.dat" ] |> Path.toAbsolute)
            , method = "POST"
            , timeout = Nothing
            }
        ]


startFetcher2 :
    ProgramConfig userMsg userModel route pageData actionData sharedData effect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Bool
    -> String
    -> Int
    -> FormData
    -> Model userModel pageData actionData sharedData
    -> Cmd (Msg userMsg pageData actionData sharedData errorPage)
startFetcher2 config fromPageReload fetcherKey transitionId formData model =
    let
        encodedBody : String
        encodedBody =
            encodeFormData formData.fields
    in
    -- TODO make sure that `actionData` isn't updated in Model for fetchers
    Cmd.batch
        [ cancelStaleFetchers model
        , case Dict.get fetcherKey model.inFlightFetchers of
            Just ( inFlightId, _ ) ->
                Http.cancel (String.fromInt inFlightId)

            Nothing ->
                Cmd.none
        , Time.now |> Task.map (FetcherStarted fetcherKey transitionId formData) |> Task.perform identity
        , Http.request
            { expect =
                Http.expectBytesResponse (FetcherComplete fromPageReload fetcherKey model.nextTransitionKey)
                    (\bytes ->
                        case bytes of
                            Http.GoodStatus_ _ bytesBody ->
                                let
                                    decodedAction : ActionDataOrRedirect actionData
                                    decodedAction =
                                        case Bytes.Decode.decode config.decodeResponse bytesBody of
                                            -- @@@
                                            Just (ResponseSketch.Redirect redirectTo) ->
                                                RedirectResponse redirectTo

                                            Just (ResponseSketch.RenderPage _ maybeAction) ->
                                                ActionResponse maybeAction

                                            Just (ResponseSketch.HotUpdate _ _ maybeAction) ->
                                                ActionResponse maybeAction

                                            Just (ResponseSketch.NotFound _) ->
                                                ActionResponse Nothing

                                            _ ->
                                                ActionResponse Nothing
                                in
                                -- TODO maybe have an optional way to pass the bytes through?
                                Ok ( Nothing, decodedAction )

                            Http.BadUrl_ string ->
                                Err <| Http.BadUrl string

                            Http.Timeout_ ->
                                Err <| Http.Timeout

                            Http.NetworkError_ ->
                                Err <| Http.NetworkError

                            Http.BadStatus_ metadata _ ->
                                Err <| Http.BadStatus metadata.statusCode
                    )
            , tracker = Just (String.fromInt transitionId)

            -- TODO use formData.method to do either query params or POST body
            , body = Http.stringBody "application/x-www-form-urlencoded" encodedBody
            , headers = []

            -- TODO use formData.method to do either query params or POST body
            , url = formData.action |> Url.fromString |> Maybe.map (\{ path } -> Path.join [ path, "content.dat" ] |> Path.toAbsolute) |> Maybe.withDefault "/"
            , method = formData.method |> methodToString
            , timeout = Nothing
            }
        ]


cancelStaleFetchers : Model userModel pageData actionData sharedData -> Cmd msg
cancelStaleFetchers model =
    model.inFlightFetchers
        |> Dict.toList
        |> List.filterMap
            (\( _, ( id, fetcher ) ) ->
                case fetcher.status of
                    Pages.Transition.FetcherReloading _ ->
                        Http.cancel (String.fromInt id)
                            |> Just

                    Pages.Transition.FetcherSubmitting ->
                        Nothing

                    Pages.Transition.FetcherComplete _ ->
                        Nothing
            )
        |> Cmd.batch


appendFormQueryParams : FormData -> String
appendFormQueryParams fields =
    (fields.action
        |> Url.fromString
        |> Maybe.map .path
        |> Maybe.withDefault "/"
    )
        ++ (case fields.method of
                Get ->
                    "?" ++ encodeFormData fields.fields

                Post ->
                    ""
           )


urlFromAction : Url -> Maybe FormData -> Url
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
                                |> Sub.map (Pages.Internal.Msg.UserMsg >> UserMsg)
                            , config.hotReloadData
                                |> Sub.map HotReloadCompleteNew
                            ]

                    Err _ ->
                        config.hotReloadData
                            |> Sub.map HotReloadCompleteNew
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


{-| -}
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
                    config.update model.pageFormState (model.inFlightFetchers |> toFetcherState) (model.transition |> Maybe.map Tuple.second) pageData.sharedData pageData.pageData model.key userMsg pageData.userModel

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
    -> Maybe FormData
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
        formMethod : Method
        formMethod =
            details
                |> Maybe.map .method
                |> Maybe.withDefault Get
    in
    Http.request
        { method = details |> Maybe.map (.method >> methodToString) |> Maybe.withDefault "GET"
        , headers = []
        , url =
            "/"
                ++ ((details
                        |> Maybe.map .action
                        |> Maybe.andThen Url.fromString
                        -- TODO what should happen when there is an action pointing to a different domain? Should it be a no-op? Log a warning?
                        |> Maybe.withDefault url
                    )
                        |> .path
                        |> chopForwardSlashes
                        |> String.split "/"
                        |> List.filter ((/=) "")
                        |> (\l -> l ++ [ "content.dat" ])
                        |> String.join "/"
                   )
                ++ (case formMethod of
                        Post ->
                            "/"

                        Get ->
                            details
                                |> Maybe.map (.fields >> encodeFormData)
                                |> Maybe.map (\encoded -> "?" ++ encoded)
                                |> Maybe.withDefault ""
                   )
                ++ (case formMethod of
                        -- TODO extract this to something unit testable
                        -- TODO make states mutually exclusive for submissions and direct URL requests (shouldn't be possible to append two query param strings)
                        Post ->
                            ""

                        Get ->
                            url.query
                                |> Maybe.map (\encoded -> "?" ++ encoded)
                                |> Maybe.withDefault ""
                   )
        , body =
            case formMethod of
                Post ->
                    let
                        urlEncodedFields : Maybe String
                        urlEncodedFields =
                            details
                                |> Maybe.map (.fields >> encodeFormData)
                    in
                    urlEncodedFields
                        |> Maybe.map (\encoded -> Http.stringBody "application/x-www-form-urlencoded" encoded)
                        |> Maybe.withDefault Http.emptyBody

                _ ->
                    Http.emptyBody
        , expect =
            Http.expectBytesResponse (\response -> ProcessFetchResponse transitionKey response toMsg)
                (\response ->
                    case response of
                        Http.BadUrl_ url_ ->
                            Err (Http.BadUrl url_)

                        Http.Timeout_ ->
                            Err Http.Timeout

                        Http.NetworkError_ ->
                            Err Http.NetworkError

                        Http.BadStatus_ _ body ->
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
                Just ( transitionKey, Pages.Transition.Loading _ _ ) ->
                    CancelRequest transitionKey

                _ ->
                    NoEffect
    in
    ( { model
        | nextTransitionKey = model.nextTransitionKey + 1
        , transition =
            ( model.nextTransitionKey
            , case model.transition of
                Just ( _, Pages.Transition.LoadAfterSubmit submitData _ _ ) ->
                    Pages.Transition.LoadAfterSubmit
                        submitData
                        (urlToGet.path |> Path.fromString)
                        Pages.Transition.Load

                Just ( _, Pages.Transition.Submitting submitData ) ->
                    Pages.Transition.LoadAfterSubmit
                        submitData
                        (urlToGet.path |> Path.fromString)
                        Pages.Transition.Load

                _ ->
                    Pages.Transition.Loading
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


clearLoadingFetchersAfterDataLoad : Int -> Model userModel pageData actionData sharedData -> Model userModel pageData actionData sharedData
clearLoadingFetchersAfterDataLoad completedTransitionId model =
    { model
        | inFlightFetchers =
            model.inFlightFetchers
                |> Dict.map
                    (\_ ( transitionId, fetcherState ) ->
                        -- TODO fetchers are never removed from the list. Need to decide how and when to remove them.
                        --(fetcherState.status /= Pages.Transition.FetcherReloading) || (transitionId > completedTransitionId)
                        case ( transitionId > completedTransitionId, fetcherState.status ) of
                            ( False, Pages.Transition.FetcherReloading actionData ) ->
                                ( transitionId
                                , { fetcherState | status = Pages.Transition.FetcherComplete actionData }
                                )

                            _ ->
                                ( transitionId, fetcherState )
                    )
    }


currentUrlWithPath : String -> Model userModel pageData actionData sharedData -> Url
currentUrlWithPath path { url } =
    { url | path = path }


loadDataAndUpdateUrl :
    ( pageData, sharedData, Maybe actionData )
    -> Maybe userMsg
    -> Url
    -> Url
    -> Bool
    -> ProgramConfig userMsg userModel route pageData actionData sharedData userEffect (Msg userMsg pageData actionData sharedData errorPage) errorPage
    -> Model userModel pageData actionData sharedData
    -> ( Model userModel pageData actionData sharedData, Effect userMsg pageData actionData sharedData userEffect errorPage )
loadDataAndUpdateUrl ( newPageData, newSharedData, newActionData ) maybeUserMsg urlWithoutRedirectResolution newUrl redirectPending config model =
    case model.pageData of
        Ok previousPageData ->
            let
                updatedPageData : { userModel : userModel, sharedData : sharedData, actionData : Maybe actionData, pageData : pageData }
                updatedPageData =
                    { userModel = userModel
                    , sharedData = newSharedData
                    , pageData = newPageData
                    , actionData = newActionData
                    }

                -- TODO use userEffect here?
                ( userModel, _ ) =
                    -- TODO if urlWithoutRedirectResolution is different from the url with redirect resolution, then
                    -- instead of calling update, call pushUrl (I think?)
                    -- TODO include user Cmd
                    config.update model.pageFormState
                        (model.inFlightFetchers |> toFetcherState)
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
                    -- TODO should these be the same (no if)?
                    if model.pendingRedirect || redirectPending then
                        { model
                            | url = newUrl
                            , pageData = Ok updatedPageData
                            , transition = Nothing
                            , pendingRedirect = False
                            , pageFormState = Dict.empty

                            --, inFlightFetchers = Dict.empty
                            , pendingData = Nothing
                        }

                    else
                        { model
                            | url = newUrl
                            , pageData = Ok updatedPageData
                            , pendingRedirect = False
                            , transition = Nothing
                            , inFlightFetchers = Dict.empty
                            , pendingData = Nothing
                        }

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
               1) in the dev server, and should show the relevant BackendTask error for the page
                  we're navigating to. This could be done more cleanly, but it's simplest to just
                  do a fresh page load and use the code path for presenting an error for a fresh page.
               2) In a production app. That means we had a successful build, so there were no BackendTask failures,
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


methodToString : Method -> String
methodToString method =
    case method of
        Get ->
            "GET"

        Post ->
            "POST"


encodeFormData : List ( String, String ) -> String
encodeFormData fields =
    fields
        |> List.map
            (\( name, value ) ->
                Url.percentEncode name ++ "=" ++ Url.percentEncode value
            )
        |> String.join "&"
