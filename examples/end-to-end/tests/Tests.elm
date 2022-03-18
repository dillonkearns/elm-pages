module Tests exposing (suite)

import Base64
import Bytes.Encode
import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Main exposing (config)
import PageServerResponse
import Pages.Flags exposing (Flags(..))
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.Platform as Platform
import Pages.Internal.ResponseSketch as ResponseSketch
import Pages.Internal.StaticHttpBody exposing (Body(..))
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
import Test exposing (Test, describe, test)
import Test.Html.Event
import Test.Html.Query
import Test.Html.Selector exposing (text)
import Url exposing (Protocol(..), Url)


suite : Test
suite =
    describe "end to end tests"
        [ --test "wire up hello" <|
          --    \() ->
          --        start "/greet?name=dillon" mockData
          --            |> ProgramTest.expectViewHas
          --                [ text "Hello dillon!"
          --                ]
          --test "redirect" <|
          --  \() ->
          --      start "/greet" mockData
          --          |> ProgramTest.ensureViewHas
          --              [ text "Login"
          --              ]
          --          |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
          --          |> ProgramTest.done
          --, Test.only <|
          --    test "redirect then login" <|
          --        \() ->
          --            start "/login" mockData
          --                --|> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
          --                |> ProgramTest.fillInDom "name" "Name" "Jane"
          --                |> ProgramTest.submitForm
          --                |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
          --                |> ProgramTest.ensureViewHas
          --                    [ text "Hello asdf!"
          --                    ]
          --                |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
          --                --|> ProgramTest.simulateDomEvent
          --                --    (Test.Html.Query.find [ Test.Html.Selector.tag "form" ])
          --                --    Test.Html.Event.submit
          --                |> ProgramTest.done
          test "redirect then login" <|
            \() ->
                start "/login" mockData
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.fillInDom "name" "Name" "Jane"
                    |> ProgramTest.submitForm
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
                    |> ProgramTest.ensureViewHas
                        [ text "Hello asdf!"
                        ]
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
                    |> ProgramTest.done
        , test "greet with cookies" <|
            \() ->
                start "/greet" mockData
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
                    |> ProgramTest.ensureViewHas
                        [ text "Hello asdf!"
                        ]
                    |> ProgramTest.done
        ]


mockData : DataSourceSimulator
mockData _ request =
    Nothing


type alias DataSourceSimulator =
    Maybe Platform.RequestInfo -> Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response


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
        appRequestSimulator : DataSourceSimulator
        appRequestSimulator maybeRequestInfo request =
            if request.url == "$$elm-pages$$headers" then
                case maybeRequestInfo of
                    Just requestInfo ->
                        RequestsAndPending.Response Nothing
                            (RequestsAndPending.JsonBody
                                (Encode.object
                                    [ ( "requestTime", Encode.int 0 )
                                    , ( "headers"
                                      , Encode.dict identity
                                            Encode.string
                                            (Dict.fromList
                                                [ ( "content-type", requestInfo.contentType )

                                                --, ( "cookie", """mysession={"name":"asdf"}""" )
                                                --, ( "cookie", """mysession=%7B%22name%22%3A%22asdf%22%7D""" )
                                                ]
                                            )
                                      )
                                    , ( "rawUrl"
                                      , Encode.string <|
                                            "https://localhost:1234/"
                                                -- TODO remove hardcoding
                                                ++ "login"
                                      )
                                    , ( "body"
                                      , Encode.string requestInfo.body
                                      )
                                    , ( "method", Encode.string "POST" )
                                    ]
                                )
                            )
                            |> Just

                    Nothing ->
                        RequestsAndPending.Response Nothing
                            (RequestsAndPending.JsonBody
                                (Encode.object
                                    [ ( "requestTime", Encode.int 0 )
                                    , ( "headers"
                                      , Encode.dict identity
                                            Encode.string
                                            (Dict.fromList
                                                [ --( "cookie", """mysession={"name":"asdf"}""" )
                                                  ( "cookie", """mysession=%7B%22name%22%3A%22asdf%22%7D""" )
                                                ]
                                            )
                                      )
                                    , ( "rawUrl"
                                      , Encode.string <|
                                            "https://localhost:1234/"
                                                -- TODO remove hardcoding
                                                ++ "greet"
                                      )
                                    , ( "body"
                                      , Encode.null
                                      )
                                    , ( "method", Encode.string "GET" )
                                    ]
                                )
                            )
                            |> Just
                --RequestsAndPending.Response Nothing
                --    (RequestsAndPending.JsonBody
                --        (Encode.object
                --            [ ( "requestTime", Encode.int 0 )
                --            , ( "headers", Encode.dict identity Encode.string Dict.empty )
                --            , ( "rawUrl", Encode.string <| "https://localhost:1234/" ++ initialPath )
                --            , ( "body", maybeRequestInfo |> Maybe.map .body |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
                --            , ( "method", Encode.string "GET" )
                --            ]
                --        )
                --    )
                --    |> Just

            else if request.url == "elm-pages-internal://env" then
                RequestsAndPending.Response Nothing
                    (RequestsAndPending.JsonBody
                        (Encode.string "")
                    )
                    |> Just

            else if request.url == "elm-pages-internal://encrypt" then
                let
                    _ =
                        case request.body of
                            JsonBody body ->
                                body
                                    |> Decode.decodeValue (Decode.field "values" (Decode.dict Decode.string))
                                    --|> Result.map (D)
                                    --|> Result.withDefault "Err"
                                    |> Debug.toString

                            _ ->
                                "NotJSON"
                in
                RequestsAndPending.Response Nothing
                    (RequestsAndPending.JsonBody
                        (case request.body of
                            JsonBody body ->
                                body
                                    |> Decode.decodeValue (Decode.field "values" (Decode.dict Decode.string))
                                    |> Result.map
                                        (Dict.toList >> List.map (\( key, value ) -> "asdf") >> String.join "; ")
                                    |> Result.withDefault "ERROR"
                                    |> Encode.string

                            _ ->
                                Encode.null
                        )
                    )
                    |> Just

            else if request.url == "elm-pages-internal://decrypt" then
                let
                    decryptResponse : Encode.Value
                    decryptResponse =
                        case request.body of
                            JsonBody body ->
                                let
                                    decoded =
                                        body
                                            |> Decode.decodeValue (Decode.field "input" Decode.string)
                                            |> Result.withDefault "INTERNAL ERROR - unexpected decrypt data"
                                            |> Decode.decodeString Decode.value
                                            |> Result.withDefault Encode.null
                                in
                                decoded

                            _ ->
                                Encode.null
                in
                RequestsAndPending.Response Nothing
                    (RequestsAndPending.JsonBody
                        decryptResponse
                    )
                    |> Just

            else
                dataSourceSimulator Nothing request

        resolvedSharedData : Shared.Data
        resolvedSharedData =
            Pages.StaticHttpRequest.mockResolve
                Shared.template.data
                (appRequestSimulator Nothing)
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
                }

        initialRouteNotFoundReason : Maybe NotFoundReason
        initialRouteNotFoundReason =
            Pages.StaticHttpRequest.mockResolve
                (config.handleRoute initialRoute)
                (appRequestSimulator Nothing)
                |> expectOk

        responseSketchData : ( Maybe String, Main.PageData )
        responseSketchData =
            initialUrlOrRedirect Nothing initialRoute appRequestSimulator Nothing
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
        , onFormSubmit =
            \_ ->
                let
                    url : Url
                    url =
                        { path = "/login" -- TODO use current URL (unless the form overrides it)
                        , query = Nothing
                        , fragment = Nothing
                        , host = "localhost"
                        , port_ = Just 1234
                        , protocol = Https
                        }
                in
                Platform.FetchPageData
                    (Just
                        { body = "name=dillon"
                        , contentType = "application/x-www-form-urlencoded"
                        }
                    )
                    --url
                    --{ url | path = "/greet" }
                    url
                    (Platform.UpdateCacheAndUrlNew False
                        url
                     --{ url | path = "/greet" }
                    )
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
                        (dataSourceSimulator maybeRequestInfo)

                newThing =
                    initialUrlOrRedirect Nothing
                        newRoute
                        dataSourceSimulator
                        maybeRequestInfo

                newThingMapped =
                    newThing
                        |> Tuple.mapSecond ResponseSketch.RenderPage
                        |> Tuple.mapFirst (Maybe.map toUrl)
                        |> Tuple.mapFirst (Maybe.withDefault url)

                toUrl : String -> Url
                toUrl path =
                    { path = path
                    , query = Nothing
                    , fragment = Nothing
                    , host = "localhost"
                    , port_ = Just 1234
                    , protocol = Https
                    }

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
                            Debug.todo <| "Unhandled: " ++ Debug.toString newDataMock

                msg : Result error ( Url, ResponseSketch.ResponseSketch Main.PageData shared )
                msg =
                    --Ok ( url, responseSketchData )
                    Ok newThingMapped
            in
            case newThing of
                ( Just redirectToUrl, _ ) ->
                    SimulatedEffect.Cmd.batch
                        [ SimulatedEffect.Task.succeed (msg |> toMsg)
                            |> SimulatedEffect.Task.perform identity
                        , SimulatedEffect.Navigation.pushUrl redirectToUrl
                        ]

                _ ->
                    SimulatedEffect.Task.succeed (msg |> toMsg)
                        |> SimulatedEffect.Task.perform identity

        --_ ->
        --    SimulatedEffect.Task.succeed (msg |> toMsg |> Debug.log "msg")
        --        |> SimulatedEffect.Task.perform identity
        Platform.UserCmd cmd ->
            -- TODO need to turn this into an `Effect` defined by user - this is a temporary intermediary step to get there
            -- TODO need to expose a way for the user to simulate their own Effect type (similar to elm-program-test's withSimulatedEffects)
            SimulatedEffect.Cmd.none


initialUrlOrRedirect : Maybe String -> Maybe Route.Route -> DataSourceSimulator -> Maybe Platform.RequestInfo -> ( Maybe String, Main.PageData )
initialUrlOrRedirect redirectedFrom newRoute dataSourceSimulator maybeRequestInfo =
    let
        newDataMock =
            Pages.StaticHttpRequest.mockResolve
                (Main.config.data newRoute)
                (dataSourceSimulator maybeRequestInfo)
    in
    case newDataMock of
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
                            -- Don't pass along the request payload to redirects
                            Nothing
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
