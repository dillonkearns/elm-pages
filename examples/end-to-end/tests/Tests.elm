module Tests exposing (suite)

import Base64
import Bytes.Encode
import CookieParser
import Dict exposing (Dict)
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import List.Extra
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
        [ test "wire up hello" <|
            \() ->
                start "/greet?name=dillon" mockData
                    |> ProgramTest.expectViewHas
                        [ text "Hello dillon!"
                        ]
        , --test "redirect" <|
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
                        [ text "Hello Jane!"
                        ]
                    |> ProgramTest.done
        ]


mockData : DataSourceSimulator
mockData _ _ _ request =
    Nothing


type alias DataSourceSimulator =
    Dict String String -> ProgramTest.SimpleState -> Maybe Platform.RequestInfo -> Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response


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
        initialSimpleState =
            { domFields = Dict.empty
            , navigation =
                Just
                    { currentLocation = toUrl initialPath
                    , browserHistory = [ toUrl initialPath ]
                    }
            , cookieJar = Dict.empty
            }

        appRequestSimulator : DataSourceSimulator
        appRequestSimulator inFlightCookies testState maybeRequestInfo request =
            if request.url == "$$elm-pages$$headers" then
                let
                    cookieHeader : ( String, String )
                    cookieHeader =
                        ( "cookie"
                        , testState.cookieJar
                            |> Dict.union inFlightCookies
                            |> Dict.toList
                            |> List.map (\( name, value ) -> name ++ "=" ++ value)
                            |> String.join ";"
                        )

                    requestTime : ( String, Encode.Value )
                    requestTime =
                        ( "requestTime", Encode.int 0 )

                    rawUrl : ( String, Encode.Value )
                    rawUrl =
                        ( "rawUrl"
                        , Encode.string <|
                            "https://localhost:1234/"
                                -- TODO handle with or without leading `/`
                                -- TODO handle URL on page change
                                ++ initialPath
                        )
                in
                case maybeRequestInfo of
                    Just requestInfo ->
                        RequestsAndPending.Response Nothing
                            (RequestsAndPending.JsonBody
                                (Encode.object
                                    [ requestTime
                                    , ( "headers"
                                      , Encode.dict identity
                                            Encode.string
                                            (Dict.fromList
                                                [ ( "content-type", requestInfo.contentType )
                                                , cookieHeader
                                                ]
                                            )
                                      )
                                    , rawUrl
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
                                    [ requestTime
                                    , ( "headers"
                                      , Encode.dict identity
                                            Encode.string
                                            (Dict.fromList
                                                [ ( "content-type", "application/x-www-form-urlencoded" )
                                                , cookieHeader
                                                ]
                                            )
                                      )
                                    , rawUrl
                                    , ( "body"
                                      , Encode.null
                                      )
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
                        (case request.body of
                            JsonBody body ->
                                body
                                    |> Decode.decodeValue (Decode.field "values" Decode.value)
                                    |> Result.withDefault Encode.null
                                    |> Encode.encode 0
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
                dataSourceSimulator
                    Dict.empty
                    { domFields = Dict.empty
                    , navigation =
                        Just
                            { currentLocation = toUrl initialPath
                            , browserHistory = [ toUrl initialPath ]
                            }
                    , cookieJar = Dict.empty
                    }
                    Nothing
                    request

        resolvedSharedData : Shared.Data
        resolvedSharedData =
            Pages.StaticHttpRequest.mockResolve
                Shared.template.data
                (appRequestSimulator Dict.empty initialSimpleState Nothing)
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
                                (responseSketchData |> tupleThird)
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
                (appRequestSimulator Dict.empty initialSimpleState Nothing)
                |> expectOk

        responseSketchData : ( Dict String String, Maybe String, Main.PageData )
        responseSketchData =
            initialUrlOrRedirect Nothing Dict.empty initialSimpleState initialRoute appRequestSimulator Nothing
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
            \formState ->
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
                        { body =
                            --"name=John"
                            formState
                                -- TODO url encode key and value (use shared helper, same one that elm-pages uses?)
                                -- TODO don't send ALL form state... send only the form state from the current form *AND* the button that was clicked to submit (if any)
                                |> Dict.toList
                                |> List.map (\( key, value ) -> key ++ "=" ++ value)
                                |> String.join "&"
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
                        |> tupleSecond
                        |> Maybe.withDefault initialPath
                   )
            )
        |> ProgramTest.withSimulatedEffects (perform appRequestSimulator)
        |> ProgramTest.start flagsWithData


tupleFirst : ( a, b, c ) -> a
tupleFirst ( a, b, c ) =
    a


tupleSecond : ( a, b, c ) -> b
tupleSecond ( a, b, c ) =
    b


tupleThird : ( a, b, c ) -> c
tupleThird ( a, b, c ) =
    c


perform :
    DataSourceSimulator
    -> ProgramTest.SimpleState
    -> Platform.Effect userMsg Main.PageData Shared.Data
    -- TODO return ( effect, CookieJarUpdate ) here?
    -> ( Dict String String, ProgramTest.SimulatedEffect (Platform.Msg userMsg Main.PageData Shared.Data) )
perform dataSourceSimulator testState effect =
    case effect of
        Platform.NoEffect ->
            ( testState.cookieJar, SimulatedEffect.Cmd.none )

        Platform.ScrollToTop ->
            ( testState.cookieJar, SimulatedEffect.Cmd.none )

        Platform.BrowserLoadUrl url ->
            ( testState.cookieJar, SimulatedEffect.Navigation.load url )

        Platform.BrowserPushUrl url ->
            ( testState.cookieJar, SimulatedEffect.Navigation.pushUrl url )

        Platform.Batch effects ->
            let
                all =
                    effects
                        |> List.map (perform dataSourceSimulator testState)

                allCookies : Dict String String
                allCookies =
                    all
                        |> List.map Tuple.first
                        -- TODO should it be foldl or foldr
                        |> List.foldl Dict.union testState.cookieJar

                batchedEffects =
                    effects
                        |> List.map (perform dataSourceSimulator testState)
                        |> List.map Tuple.second
                        |> SimulatedEffect.Cmd.batch
            in
            ( allCookies
            , batchedEffects
            )

        Platform.FetchPageData maybeRequestInfo url toMsg ->
            let
                newRoute : Maybe Route.Route
                newRoute =
                    Main.config.urlToRoute url

                newThing : ( Dict String String, Maybe String, Main.PageData )
                newThing =
                    initialUrlOrRedirect Nothing
                        testState.cookieJar
                        testState
                        newRoute
                        dataSourceSimulator
                        maybeRequestInfo

                newThingMapped : ( Dict String String, Url, ResponseSketch.ResponseSketch Main.PageData Shared.Data )
                newThingMapped =
                    case newThing of
                        ( a, b, c ) ->
                            ( a
                            , b
                                |> Maybe.map toUrl
                                |> Maybe.withDefault url
                            , ResponseSketch.RenderPage c
                            )

                --|> Tuple.mapSecond ResponseSketch.RenderPage
                --|> Tuple.mapFirst (Maybe.map toUrl)
                --|> Tuple.mapFirst (Maybe.withDefault url)
                msg : Result error ( Url, ResponseSketch.ResponseSketch Main.PageData Shared.Data )
                msg =
                    case newThingMapped of
                        ( _, b, c ) ->
                            Ok ( b, c )
            in
            case newThing of
                ( _, Just redirectToUrl, _ ) ->
                    ( testState.cookieJar
                        |> Dict.union (tupleFirst newThing)
                    , SimulatedEffect.Cmd.batch
                        [ SimulatedEffect.Task.succeed (msg |> toMsg)
                            |> SimulatedEffect.Task.perform identity
                        , SimulatedEffect.Navigation.pushUrl redirectToUrl
                        ]
                    )

                _ ->
                    ( testState.cookieJar
                        |> Dict.union (tupleFirst newThing)
                    , SimulatedEffect.Task.succeed (msg |> toMsg)
                        |> SimulatedEffect.Task.perform identity
                    )

        Platform.UserCmd cmd ->
            -- TODO need to turn this into an `Effect` defined by user - this is a temporary intermediary step to get there
            -- TODO need to expose a way for the user to simulate their own Effect type (similar to elm-program-test's withSimulatedEffects)
            ( testState.cookieJar, SimulatedEffect.Cmd.none )


initialUrlOrRedirect :
    Maybe String
    -> Dict String String
    -> ProgramTest.SimpleState
    -> Maybe Route.Route
    -> DataSourceSimulator
    -> Maybe Platform.RequestInfo
    ->
        ( Dict String String
        , Maybe String
        , Main.PageData
        )
initialUrlOrRedirect redirectedFrom cookiesSoFar testState newRoute dataSourceSimulator maybeRequestInfo =
    let
        newDataMock =
            Pages.StaticHttpRequest.mockResolve
                (Main.config.data newRoute)
                (dataSourceSimulator cookiesSoFar testState maybeRequestInfo)
    in
    case newDataMock of
        Ok (PageServerResponse.RenderPage info newPageData) ->
            ( cookiesSoFar
                |> Dict.union (getCookies info)
            , redirectedFrom
            , newPageData
            )

        Ok (PageServerResponse.ServerResponse info) ->
            PageServerResponse.toRedirect info
                |> Maybe.map
                    (\{ location } ->
                        location
                    )
                |> expectJust
                |> (\location ->
                        initialUrlOrRedirect (Just location)
                            (cookiesSoFar |> Dict.union (getCookies info))
                            testState
                            (Main.config.urlToRoute { path = location })
                            dataSourceSimulator
                            -- Don't pass along the request payload to redirects
                            Nothing
                   )

        _ ->
            Debug.todo <| "Unhandled: " ++ Debug.toString newDataMock


getCookies : { a | headers : List ( String, String ) } -> Dict String String
getCookies info =
    info.headers
        |> List.filterMap
            (\( key, value ) ->
                if String.toLower key == "set-cookie" then
                    case
                        value
                            |> String.split ";"
                            |> List.head
                            |> Maybe.withDefault value
                            |> String.split "="
                    of
                        [ setCookieKey, setCookieValue ] ->
                            Just ( setCookieKey, setCookieValue )

                        _ ->
                            Nothing

                else
                    Nothing
            )
        |> Dict.fromList


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


toUrl : String -> Url
toUrl path =
    { path = path
    , query = Nothing
    , fragment = Nothing
    , host = "localhost"
    , port_ = Just 1234
    , protocol = Https
    }
