module Tests exposing (suite)

import Base64
import Bytes.Encode
import Expect
import Json.Encode as Encode
import Main exposing (config)
import PageServerResponse
import Pages.Flags exposing (Flags(..))
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.Platform as Platform
import Pages.Internal.ResponseSketch as ResponseSketch
import Pages.StaticHttp.Request
import Pages.StaticHttpRequest
import Path
import ProgramTest
import RequestsAndPending
import Route
import Shared
import SimulatedEffect.Cmd
import SimulatedEffect.Navigation
import SimulatedEffect.Task
import Test exposing (Test, describe, only, test)
import Test.Html.Selector exposing (text)
import Url exposing (Url)


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


start :
    String
    -> BackendTaskSimulator
    ->
        ProgramTest.ProgramTest
            (Platform.Model Main.Model Main.PageData Shared.Data)
            (Platform.Msg Main.Msg Main.PageData Shared.Data)
            (Platform.Effect Main.Msg Main.PageData Shared.Data)
start initialPath backendTaskSimulator =
    let
        resolvedSharedData : Shared.Data
        resolvedSharedData =
            Pages.StaticHttpRequest.mockResolve
                Shared.template.data
                backendTaskSimulator
                |> expectOk

        flagsWithData =
            Encode.object
                [ ( "pageDataBase64"
                  , (case initialRouteNotFoundReason of
                        Just notFoundReason ->
                            { reason = notFoundReason
                            , path = Path.fromString initialPath
                            }
                                |> ResponseSketch.NotFound

                        Nothing ->
                            ResponseSketch.HotUpdate
                                responseSketchData
                                resolvedSharedData
                    )
                        |> Main.encodeResponse
                        |> Bytes.Encode.encode
                        |> Base64.fromBytes
                        |> expectJust
                        |> Encode.string
                  )
                ]

        initialRoute : Maybe Route.Route
        initialRoute =
            Main.config.urlToRoute { path = initialPath }

        initialRouteNotFoundReason : Maybe NotFoundReason
        initialRouteNotFoundReason =
            Pages.StaticHttpRequest.mockResolve
                (config.handleRoute initialRoute)
                backendTaskSimulator
                |> expectOk

        newDataMock : Result Pages.StaticHttpRequest.Error (PageServerResponse.PageServerResponse Main.PageData)
        newDataMock =
            Pages.StaticHttpRequest.mockResolve
                (Main.config.data initialRoute)
                backendTaskSimulator

        responseSketchData : Main.PageData
        responseSketchData =
            case newDataMock of
                Ok (PageServerResponse.RenderPage info newPageData) ->
                    newPageData

                _ ->
                    Debug.todo "Unhandled"
    in
    ProgramTest.createApplication
        { onUrlRequest = Platform.LinkClicked
        , onUrlChange = Platform.UrlChanged
        , init =
            \flags url () ->
                Platform.init Main.config flags url Nothing
        , update =
            \msg model ->
                Platform.update Main.config msg model
        , view =
            \model ->
                Platform.view Main.config model
        }
        |> ProgramTest.withBaseUrl ("https://localhost:1234" ++ initialPath)
        |> ProgramTest.withSimulatedEffects (perform backendTaskSimulator)
        |> ProgramTest.start flagsWithData


perform :
    BackendTaskSimulator
    -> Platform.Effect userMsg Main.PageData Shared.Data
    -> ProgramTest.SimulatedEffect (Platform.Msg userMsg Main.PageData Shared.Data)
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

        Platform.Batch effects ->
            effects
                |> List.map (perform backendTaskSimulator)
                |> SimulatedEffect.Cmd.batch

        Platform.FetchPageData maybeRequestInfo url toMsg ->
            let
                newRoute : Maybe Route.Route
                newRoute =
                    Main.config.urlToRoute url

                newDataMock : Result Pages.StaticHttpRequest.Error (PageServerResponse.PageServerResponse Main.PageData)
                newDataMock =
                    Pages.StaticHttpRequest.mockResolve
                        (Main.config.data newRoute)
                        backendTaskSimulator

                responseSketchData : ResponseSketch.ResponseSketch Main.PageData shared
                responseSketchData =
                    case newDataMock of
                        Ok (PageServerResponse.RenderPage info newPageData) ->
                            ResponseSketch.RenderPage newPageData

                        _ ->
                            Debug.todo "Unhandled"

                msg : Result error ( Url, ResponseSketch.ResponseSketch Main.PageData shared )
                msg =
                    Ok ( url, responseSketchData )
            in
            SimulatedEffect.Task.succeed msg
                |> SimulatedEffect.Task.perform toMsg

        Platform.UserCmd cmd ->
            -- TODO need to turn this into an `Effect` defined by user - this is a temporary intermediary step to get there
            -- TODO need to expose a way for the user to simulate their own Effect type (similar to elm-program-test's withSimulatedEffects)
            SimulatedEffect.Cmd.none


expectJust : Maybe a -> a
expectJust maybeValue =
    case maybeValue of
        Just justThing ->
            justThing

        Nothing ->
            Debug.todo "Expected Just but got Nothing"


expectOk : Result error a -> a
expectOk thing =
    case thing of
        Ok okThing ->
            okThing

        Err error ->
            Debug.todo <| "Expected Ok but got Err " ++ Debug.toString error
