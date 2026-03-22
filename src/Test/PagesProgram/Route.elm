module Test.PagesProgram.Route exposing
    ( fromStatefulRoute
    , testRequest
    , unwrapResponse
    , makeApp
    , mapPagesMsg
    )

{-| Utilities for adapting elm-pages route modules for use with
[`Test.PagesProgram`](Test-PagesProgram). The main entry point is
[`fromStatefulRoute`](#fromStatefulRoute), which the generated `TestApp`
module uses. Most users won't need to import this module directly.

@docs fromStatefulRoute

@docs testRequest, unwrapResponse, makeApp, mapPagesMsg

-}

import BackendTask exposing (BackendTask)
import Dict
import FatalError exposing (FatalError)
import Html exposing (Html)
import Http
import Internal.Request
import PageServerResponse exposing (PageServerResponse(..))
import Pages.ConcurrentSubmission
import Pages.Fetcher exposing (Fetcher(..))
import Pages.Internal.Msg
import Pages.Navigation
import Time
import UrlPath


{-| Adapt a route's `StatefulRoute` record into the config format that
`Test.PagesProgram.start` expects. This is the core adapter -- one function
handles all route types (static, dynamic, stateless, stateful, single,
preRender, serverRender) because `RouteBuilder` normalizes them all to the
same field signatures.

The generated `TestApp` module calls this for each route:

    -- Generated TestApp.elm
    index routeParams =
        Test.PagesProgram.Route.fromStatefulRoute projectConfig
            Route.Index.route
            routeParams

The `projectConfig` record provides project-specific adapters that are
defined once and shared across all routes.

-}
fromStatefulRoute projectConfig route routeParams =
    let
        toApp pageData =
            makeApp
                { data = pageData
                , sharedData = projectConfig.sharedData
                , routeParams = routeParams
                , path = ""
                }
    in
    { data =
        route.data testRequest routeParams
            |> BackendTask.andThen unwrapResponse
    , init =
        \pageData ->
            let
                ( model, effect ) =
                    route.init projectConfig.defaultShared (toApp pageData)
            in
            -- Wrap the model with pageData so update can access it
            ( ( pageData, model ), projectConfig.extractEffects effect )
    , update =
        \msg ( pageData, model ) ->
            let
                ( newModel, effect, _ ) =
                    route.update (toApp pageData) msg model projectConfig.defaultShared
            in
            ( ( pageData, newModel ), projectConfig.extractEffects effect )
    , view =
        \_ ( pageData, model ) ->
            -- view receives the pageData from the wrapped model, not the
            -- data argument (which is also pageData, just from a different path)
            projectConfig.viewToHtml
                (route.view projectConfig.defaultShared model (toApp pageData))
    }


{-| A fake `Server.Request.Request` for testing. Uses a GET method with an
empty body and no headers or cookies.
-}
testRequest : Internal.Request.Request
testRequest =
    Internal.Request.Request
        { time = Time.millisToPosix 0
        , method = "GET"
        , body = Nothing
        , rawUrl = "http://localhost:1234/"
        , rawHeaders = Dict.empty
        , cookies = Dict.empty
        }


{-| Unwrap a `PageServerResponse` into its data value. If the response
is a redirect or error page, the BackendTask fails with a descriptive error.
-}
unwrapResponse : PageServerResponse data error -> BackendTask FatalError data
unwrapResponse response =
    case response of
        RenderPage _ pageData ->
            BackendTask.succeed pageData

        ServerResponse serverResponse ->
            BackendTask.fail
                (FatalError.fromString
                    ("Expected a rendered page but got a server response with status "
                        ++ String.fromInt serverResponse.statusCode
                    )
                )

        PageServerResponse.ErrorPage _ _ ->
            BackendTask.fail
                (FatalError.fromString "Expected a rendered page but got an error page")


{-| Construct an `App`-compatible record for use with route view/init/update
functions. The record is structurally compatible with `RouteBuilder.App`.
-}
makeApp :
    { data : data
    , sharedData : sharedData
    , routeParams : routeParams
    , path : String
    }
    ->
        { data : data
        , sharedData : sharedData
        , routeParams : routeParams
        , path : UrlPath.UrlPath
        , url : Maybe a
        , action : Maybe action
        , submit :
            { fields : List ( String, String ), headers : List ( String, String ) }
            -> Fetcher (Result Http.Error action)
        , navigation : Maybe Pages.Navigation.Navigation
        , concurrentSubmissions :
            Dict.Dict
                String
                (Pages.ConcurrentSubmission.ConcurrentSubmission (Maybe action))
        , pageFormState : Dict.Dict String b
        }
makeApp config =
    { data = config.data
    , sharedData = config.sharedData
    , routeParams = config.routeParams
    , path = UrlPath.fromString config.path
    , url = Nothing
    , action = Nothing
    , submit =
        \_ ->
            Fetcher
                { decoder = \_ -> Err (Http.BadUrl "test stub")
                , fields = []
                , headers = []
                , url = Nothing
                }
    , navigation = Nothing
    , concurrentSubmissions = Dict.empty
    , pageFormState = Dict.empty
    }


{-| Extract the user message from a `PagesMsg`, discarding framework messages
(`NoOp`, `Submit`, `FormMsg`). Returns `Nothing` for non-user messages.
-}
mapPagesMsg : Pages.Internal.Msg.Msg userMsg -> Maybe userMsg
mapPagesMsg pagesMsg =
    case pagesMsg of
        Pages.Internal.Msg.UserMsg msg ->
            Just msg

        _ ->
            Nothing


