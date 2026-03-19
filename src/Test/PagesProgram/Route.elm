module Test.PagesProgram.Route exposing
    ( testRequest
    , unwrapResponse
    , makeApp
    , mapPagesMsg
    )

{-| Utilities for adapting elm-pages route modules for use with
[`Test.PagesProgram`](Test-PagesProgram). These are used by the generated
`TestApp` module -- most users won't need to import this module directly.

@docs testRequest, unwrapResponse, makeApp, mapPagesMsg

-}

import BackendTask exposing (BackendTask)
import Dict
import FatalError exposing (FatalError)
import Http
import Internal.Request
import PageServerResponse exposing (PageServerResponse(..))
import Pages.ConcurrentSubmission
import Pages.Fetcher exposing (Fetcher(..))
import Pages.Internal.Msg
import Pages.Navigation
import Time
import UrlPath


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
