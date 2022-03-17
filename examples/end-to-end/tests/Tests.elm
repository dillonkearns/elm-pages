module Tests exposing (suite)

import Base64
import Bytes.Encode
import Dict
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
import Regex
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
                start "/greet?name=dillon" mockData
                    |> ProgramTest.expectViewHas
                        [ text "Hello dillon!"
                        ]
        , test "redirect" <|
            \() ->
                start "/greet" mockData
                    |> ProgramTest.ensureViewHas
                        [ text "Login"
                        ]
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.done
        ]


mockData : Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response
mockData request =
    Nothing


type alias DataSourceSimulator =
    Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response


start :
    String
    -> DataSourceSimulator
    ->
        ProgramTest.ProgramTest
            (Platform.Model Main.Model Main.PageData Shared.Data)
            (Platform.Msg Main.Msg Main.PageData Shared.Data)
            (Platform.Effect Main.Msg Main.PageData Shared.Data)
start initialPath dataSourceSimulator =
    let
        appRequestSimulator : Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response
        appRequestSimulator request =
            if request.url == "$$elm-pages$$headers" then
                RequestsAndPending.Response Nothing
                    (RequestsAndPending.JsonBody
                        (Encode.object
                            [ ( "requestTime", Encode.int 0 )
                            , ( "headers", Encode.dict identity Encode.string Dict.empty )
                            , ( "rawUrl", Encode.string <| "https://localhost:1234/" ++ initialPath )
                            , ( "body", Encode.null )
                            , ( "method", Encode.string "GET" )
                            ]
                        )
                    )
                    |> Just

            else if request.url == "elm-pages-internal://env" then
                RequestsAndPending.Response Nothing
                    (RequestsAndPending.JsonBody
                        (Encode.string "")
                    )
                    |> Just

            else if request.url == "elm-pages-internal://encrypt" then
                RequestsAndPending.Response Nothing
                    (RequestsAndPending.JsonBody
                        (Encode.string "")
                    )
                    |> Just

            else
                dataSourceSimulator request

        resolvedSharedData : Shared.Data
        resolvedSharedData =
            Pages.StaticHttpRequest.mockResolve
                Shared.template.data
                appRequestSimulator
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
                                (responseSketchData |> Tuple.second)
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
            Main.config.urlToRoute
                { path =
                    initialPath
                        |> Regex.replace
                            (Regex.fromString "\\?.*" |> Maybe.withDefault Regex.never)
                            (\_ -> "")
                        |> Debug.log "initialPath"
                }
                |> Debug.log "initialRoute"

        initialRouteNotFoundReason : Maybe NotFoundReason
        initialRouteNotFoundReason =
            Pages.StaticHttpRequest.mockResolve
                (config.handleRoute initialRoute)
                appRequestSimulator
                |> expectOk

        newDataMock : Result Pages.StaticHttpRequest.Error (PageServerResponse.PageServerResponse Main.PageData)
        newDataMock =
            Pages.StaticHttpRequest.mockResolve
                (Main.config.data initialRoute)
                appRequestSimulator

        responseSketchData : ( Maybe String, Main.PageData )
        responseSketchData =
            initialUrlOrRedirect Nothing initialRoute appRequestSimulator
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
        |> ProgramTest.withBaseUrl
            ("https://localhost:1234"
                ++ (responseSketchData
                        |> Tuple.first
                        |> Maybe.withDefault initialPath
                   )
            )
        |> ProgramTest.withSimulatedEffects (perform appRequestSimulator)
        |> ProgramTest.start flagsWithData


perform :
    DataSourceSimulator
    -> Platform.Effect userMsg Main.PageData Shared.Data
    -> ProgramTest.SimulatedEffect (Platform.Msg userMsg Main.PageData Shared.Data)
perform dataSourceSimulator effect =
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
                |> List.map (perform dataSourceSimulator)
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
                        dataSourceSimulator
                        |> Debug.log "@@@newDataMock"

                responseSketchData : ResponseSketch.ResponseSketch Main.PageData shared
                responseSketchData =
                    case newDataMock of
                        Ok (PageServerResponse.RenderPage info newPageData) ->
                            ResponseSketch.RenderPage newPageData

                        Ok (PageServerResponse.ServerResponse info) ->
                            PageServerResponse.toRedirect info
                                |> Maybe.map
                                    (\{ location } ->
                                        location
                                            |> ResponseSketch.Redirect
                                    )
                                |> expectJust

                        _ ->
                            Debug.todo "Unhandled"

                msg : Result error ( Url, ResponseSketch.ResponseSketch Main.PageData shared )
                msg =
                    Ok ( url, responseSketchData )
            in
            SimulatedEffect.Task.succeed (msg |> toMsg |> Debug.log "msg")
                |> SimulatedEffect.Task.perform identity

        Platform.UserCmd cmd ->
            -- TODO need to turn this into an `Effect` defined by user - this is a temporary intermediary step to get there
            -- TODO need to expose a way for the user to simulate their own Effect type (similar to elm-program-test's withSimulatedEffects)
            SimulatedEffect.Cmd.none


toResponseSketch : Maybe Route.Route -> (Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response) -> Main.PageData
toResponseSketch newRoute dataSourceSimulator =
    let
        newDataMock =
            Pages.StaticHttpRequest.mockResolve
                (Main.config.data newRoute)
                dataSourceSimulator
    in
    case newDataMock of
        Ok (PageServerResponse.RenderPage info newPageData) ->
            newPageData

        Ok (PageServerResponse.ServerResponse info) ->
            PageServerResponse.toRedirect info
                |> Maybe.map
                    (\{ location } ->
                        location
                    )
                |> expectJust
                |> (\location ->
                        toResponseSketch
                            (Main.config.urlToRoute { path = location })
                            dataSourceSimulator
                   )

        _ ->
            Debug.todo <| "Unhandled: " ++ Debug.toString newDataMock


initialUrlOrRedirect : Maybe String -> Maybe Route.Route -> (Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response) -> ( Maybe String, Main.PageData )
initialUrlOrRedirect redirectedFrom newRoute dataSourceSimulator =
    let
        newDataMock =
            Pages.StaticHttpRequest.mockResolve
                (Main.config.data newRoute)
                dataSourceSimulator
    in
    case newDataMock |> Debug.log "newDataMock" of
        Ok (PageServerResponse.RenderPage info newPageData) ->
            ( redirectedFrom, newPageData )

        Ok (PageServerResponse.ServerResponse info) ->
            PageServerResponse.toRedirect info
                |> Maybe.map
                    (\{ location } ->
                        location
                    )
                |> expectJust
                |> (\location ->
                        initialUrlOrRedirect (Just location)
                            (Main.config.urlToRoute { path = location })
                            dataSourceSimulator
                   )

        _ ->
            Debug.todo <| "Unhandled: " ++ Debug.toString newDataMock


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
