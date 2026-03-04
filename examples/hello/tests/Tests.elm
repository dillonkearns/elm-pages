module Tests exposing (suite)

import Bytes exposing (Bytes)
import Bytes.Encode
import Expect
import Json.Encode as Encode
import Main exposing (config)
import PageServerResponse
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.Platform as Platform
import Pages.Internal.ResponseSketch as ResponseSketch
import Pages.StaticHttp.Request
import Pages.StaticHttpRequest
import ProgramTest
import RequestsAndPending
import Route
import Shared
import SimulatedEffect.Cmd
import SimulatedEffect.Navigation
import SimulatedEffect.Task
import Test exposing (Test, describe, test)
import Test.Html.Selector exposing (text)
import Url exposing (Url)
import UrlPath


suite : Test
suite =
    describe "end to end tests"
        [ test "wire up hello" <|
            \() ->
                start "/" mockData
                    |> ProgramTest.ensureViewHas
                        [ text "elm-pages is up and running!"
                        , text "The message is: This is my message!!"
                        ]
                    |> ProgramTest.clickButton "Open Menu"
                    |> ProgramTest.clickButton "Close Menu"
                    |> ProgramTest.expectViewHas
                        [ text "Open Menu"
                        ]
        , test "data is fetched when navigating to new Route" <|
            \() ->
                start "/" mockData
                    |> ProgramTest.ensureBrowserUrl (\currentUrl -> currentUrl |> Expect.equal "https://localhost:1234/")
                    |> ProgramTest.routeChange "/blog/hello"
                    -- TODO elm-program-test does not yet intercept link clicks when using Browser.application
                    --  see <https://github.com/avh4/elm-program-test/issues/107>
                    --|> ProgramTest.clickLink "My blog post" "/blog/hello"
                    |> ProgramTest.ensureBrowserUrl (\currentUrl -> currentUrl |> Expect.equal "https://localhost:1234/blog/hello")
                    |> ProgramTest.expectViewHas
                        [ text "You're on the page Blog.Slug_"
                        ]
        , test "initial page blog" <|
            \() ->
                start "/blog/hello" mockData
                    |> ProgramTest.ensureBrowserUrl (\currentUrl -> currentUrl |> Expect.equal "https://localhost:1234/blog/hello")
                    |> ProgramTest.expectViewHas
                        [ text "You're on the page Blog.Slug_"
                        ]
        ]


mockData : Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response
mockData request =
    RequestsAndPending.Response Nothing
        (RequestsAndPending.JsonBody
            (Encode.object
                [ ( "message", Encode.string "This is my message!!" )
                ]
            )
        )
        |> Just


type alias BackendTaskSimulator =
    Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response


start initialPath backendTaskSimulator =
    let
        resolvedSharedData : Shared.Data
        resolvedSharedData =
            Pages.StaticHttpRequest.mockResolve
                Shared.template.data
                backendTaskSimulator
                |> expectOk

        initialRoute : Maybe Route.Route
        initialRoute =
            Main.config.urlToRoute { path = initialPath }

        initialRouteNotFoundReason : Maybe NotFoundReason
        initialRouteNotFoundReason =
            Pages.StaticHttpRequest.mockResolve
                (config.handleRoute initialRoute)
                backendTaskSimulator
                |> expectOk

        newDataMock =
            Pages.StaticHttpRequest.mockResolve
                (Main.config.data initialRoute)
                backendTaskSimulator

        responseSketchData =
            case newDataMock of
                Ok (PageServerResponse.RenderPage info newPageData) ->
                    newPageData

                _ ->
                    Debug.todo "Unhandled"

        pageDataBytes : Bytes
        pageDataBytes =
            (case initialRouteNotFoundReason of
                Just notFoundReason ->
                    { reason = notFoundReason
                    , path = UrlPath.fromString initialPath
                    }
                        |> ResponseSketch.NotFound

                Nothing ->
                    ResponseSketch.HotUpdate
                        responseSketchData
                        resolvedSharedData
                        Nothing
            )
                |> Main.config.encodeResponse
                |> Bytes.Encode.encode
    in
    ProgramTest.createApplication
        { onUrlRequest = Platform.LinkClicked
        , onUrlChange = Platform.UrlChanged
        , init =
            \flags url () ->
                let
                    ( model, initEffect ) =
                        Platform.init Main.config flags url Nothing

                    ( readyModel, readyEffect ) =
                        Platform.update Main.config (Platform.FrozenViewsReady (Just pageDataBytes)) model
                in
                ( readyModel, Platform.Batch [ initEffect, readyEffect ] )
        , update =
            \msg model ->
                Platform.update Main.config msg model
        , view =
            \model ->
                Platform.view Main.config model
        }
        |> ProgramTest.withBaseUrl ("https://localhost:1234" ++ initialPath)
        |> ProgramTest.withSimulatedEffects (perform backendTaskSimulator)
        |> ProgramTest.start (Encode.object [])


perform backendTaskSimulator effect =
    case effect of
        Platform.NoEffect ->
            SimulatedEffect.Cmd.none

        Platform.ScrollToTop ->
            SimulatedEffect.Cmd.none

        Platform.BrowserLoadUrl url ->
            SimulatedEffect.Navigation.load url

        Platform.BrowserPushUrl url ->
            SimulatedEffect.Navigation.pushUrl url

        Platform.BrowserReplaceUrl _ ->
            SimulatedEffect.Cmd.none

        Platform.Batch effects ->
            effects
                |> List.map (perform backendTaskSimulator)
                |> SimulatedEffect.Cmd.batch

        Platform.FetchFrozenViews { path } ->
            let
                newRoute =
                    Main.config.urlToRoute { path = path }

                newDataMock =
                    Pages.StaticHttpRequest.mockResolve
                        (Main.config.data newRoute)
                        backendTaskSimulator

                encodedBytes =
                    (case newDataMock of
                        Ok (PageServerResponse.RenderPage _ newPageData) ->
                            ResponseSketch.RenderPage newPageData Nothing

                        _ ->
                            Debug.todo "Unhandled"
                    )
                        |> Main.config.encodeResponse
                        |> Bytes.Encode.encode
            in
            SimulatedEffect.Task.succeed (Platform.FrozenViewsReady (Just encodedBytes))
                |> SimulatedEffect.Task.perform identity

        Platform.UserCmd _ ->
            SimulatedEffect.Cmd.none

        Platform.Submit _ ->
            SimulatedEffect.Cmd.none

        Platform.SubmitFetcher _ _ _ ->
            SimulatedEffect.Cmd.none

        Platform.CancelRequest _ ->
            SimulatedEffect.Cmd.none

        Platform.RunCmd _ ->
            SimulatedEffect.Cmd.none


expectOk : Result error a -> a
expectOk thing =
    case thing of
        Ok okThing ->
            okThing

        Err error ->
            Debug.todo <| "Expected Ok but got Err " ++ Debug.toString error
