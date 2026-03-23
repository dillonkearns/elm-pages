module PagesProgramTest exposing (all)

import BackendTask
import BackendTask.Http
import CookieJar
import Dict
import Expect exposing (Expectation)
import FatalError
import Html
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.Html.Selector as Selector
import Test.BackendTask as BackendTaskTest
import Test.BackendTask exposing (HttpError(..))
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.SimulatedSub as SimulatedSub
import Test.Runner


all : Test
all =
    describe "Test.PagesProgram"
        [ describe "Step 1: static page rendering"
            [ test "renders a page with auto-resolved data" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed "Hello, World!"
                        , init = \greeting -> ( { greeting = greeting }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Home", body = [ Html.text model.greeting ] }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Hello, World!" ]
                        |> PagesProgram.done
            , test "renders a page with unit data" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Static content" ] }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Static content" ]
                        |> PagesProgram.done
            , test "can assert on HTML structure" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body =
                                    [ Html.div [ Attr.id "main" ]
                                        [ Html.h1 [] [ Html.text "Welcome" ]
                                        , Html.p [ Attr.class "intro" ] [ Html.text "This is elm-pages" ]
                                        ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.id "main" ]
                        |> PagesProgram.ensureViewHas [ Selector.tag "h1", Selector.text "Welcome" ]
                        |> PagesProgram.ensureViewHas [ Selector.class "intro" ]
                        |> PagesProgram.ensureViewHasNot [ Selector.text "Error" ]
                        |> PagesProgram.done
            , test "data value flows through init into model and view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed { name = "Alice", role = "Admin" }
                        , init = \user -> ( user, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ model ->
                                { title = model.name
                                , body =
                                    [ Html.text (model.name ++ " (" ++ model.role ++ ")")
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Alice (Admin)" ]
                        |> PagesProgram.done
            ]
        , describe "Step 2: data BackendTask with HTTP simulation"
            [ test "resolves data with simulated HTTP GET" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/user"
                                (Decode.field "name" Decode.string)
                                |> BackendTask.allowFatal
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.simulateHttpGet
                            "https://api.example.com/user"
                            (Encode.object [ ( "name", Encode.string "Alice" ) ])
                        |> PagesProgram.ensureViewHas [ Selector.text "Alice" ]
                        |> PagesProgram.done
            , test "done fails when data BackendTask is unresolved" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/user"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.done
                        |> expectFailContaining "still resolving"
            , test "ensureViewHas fails with helpful message when data not resolved" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/user"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Alice" ]
                        |> PagesProgram.done
                        |> expectFailContaining "Cannot check view"
            ]
        , describe "Step 3: user interaction"
            [ test "clicking a button updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { count = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Increment ->
                                        ( { model | count = model.count + 1 }, [] )

                                    Decrement ->
                                        ( { model | count = model.count - 1 }, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.text (String.fromInt model.count)
                                    , Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    , Html.button [ Html.Events.onClick Decrement ] [ Html.text "-1" ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "0" ]
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ Selector.text "1" ]
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ Selector.text "3" ]
                        |> PagesProgram.clickButton "-1"
                        |> PagesProgram.ensureViewHas [ Selector.text "2" ]
                        |> PagesProgram.done
            , test "clickButton fails with helpful message for missing button" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body = [ Html.text "No buttons here" ]
                                }
                        }
                        |> PagesProgram.clickButton "Submit"
                        |> PagesProgram.done
                        |> expectFailContaining "clickButton \"Submit\""
            ]
        , describe "fillIn"
            [ test "typing into an input updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { query = "" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    UpdateQuery q ->
                                        ( { model | query = q }, [] )
                        , view =
                            \_ model ->
                                { title = "Search"
                                , body =
                                    [ Html.input
                                        [ Attr.id "search"
                                        , Attr.value model.query
                                        , Html.Events.onInput UpdateQuery
                                        ]
                                        []
                                    , if String.isEmpty model.query then
                                        Html.text "Type to search..."

                                      else
                                        Html.text ("Searching for: " ++ model.query)
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Type to search..." ]
                        |> PagesProgram.fillIn "search" "search" "elm-pages"
                        |> PagesProgram.ensureViewHas [ Selector.text "Searching for: elm-pages" ]
                        |> PagesProgram.done
            ]
        , describe "resolveEffect"
            [ test "resolves a BackendTask effect from update" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { stars = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    FetchStars ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                                (Decode.field "stargazers_count" Decode.int)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotStars
                                          ]
                                        )

                                    GotStars count ->
                                        ( { model | stars = Just count }, [] )
                        , view =
                            \_ model ->
                                { title = "Stars"
                                , body =
                                    [ case model.stars of
                                        Nothing ->
                                            Html.button [ Html.Events.onClick FetchStars ] [ Html.text "Load Stars" ]

                                        Just count ->
                                            Html.text ("Stars: " ++ String.fromInt count)
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Load Stars" ]
                        |> PagesProgram.clickButton "Load Stars"
                        |> PagesProgram.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                (Encode.object [ ( "stargazers_count", Encode.int 1234 ) ])
                            )
                        |> PagesProgram.ensureViewHas [ Selector.text "Stars: 1234" ]
                        |> PagesProgram.done
            ]
        , describe "check"
            [ test "checking a checkbox updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { agreed = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    ToggleAgreed checked ->
                                        ( { model | agreed = checked }, [] )
                        , view =
                            \_ model ->
                                { title = "Form"
                                , body =
                                    [ Html.input
                                        [ Attr.id "agree"
                                        , Attr.type_ "checkbox"
                                        , Attr.checked model.agreed
                                        , Html.Events.onCheck ToggleAgreed
                                        ]
                                        []
                                    , if model.agreed then
                                        Html.text "Terms accepted"

                                      else
                                        Html.text "Please accept terms"
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Please accept terms" ]
                        |> PagesProgram.check "agree" True
                        |> PagesProgram.ensureViewHas [ Selector.text "Terms accepted" ]
                        |> PagesProgram.done
            ]
        , describe "Snapshots"
            [ test "toSnapshots records init snapshot" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal [ "start" ]
            , test "toSnapshots records each interaction" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { count = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Increment ->
                                        ( { model | count = model.count + 1 }, [] )

                                    Decrement ->
                                        ( { model | count = model.count - 1 }, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.text (String.fromInt model.count)
                                    , Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ Selector.text "2" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal [ "start", "clickButton \"+1\"", "clickButton \"+1\"", "ensureViewHas [1 selector(s)]" ]
            , test "snapshots contain rendered HTML" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { count = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Increment ->
                                        ( { model | count = model.count + 1 }, [] )

                                    Decrement ->
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Count: " ++ String.fromInt model.count
                                , body =
                                    [ Html.text ("Count: " ++ String.fromInt model.count)
                                    , Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.toSnapshots
                        |> List.map .title
                        |> Expect.equal [ "Count: 0", "Count: 1" ]
            , test "error snapshots include the error" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.clickButton "Missing"
                        |> PagesProgram.toSnapshots
                        |> List.length
                        |> Expect.equal 2
            ]
        , describe "disabled button detection"
            [ test "clickButton fails on disabled button" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Form"
                                , body =
                                    [ Html.button
                                        [ Attr.disabled True ]
                                        [ Html.text "Submit" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Submit"
                        |> PagesProgram.done
                        |> expectFailContaining "disabled"
            , test "clickButton succeeds on enabled button" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { clicked = False }, [] )
                        , update =
                            \_ model -> ( { model | clicked = True }, [] )
                        , view =
                            \_ model ->
                                { title = "Form"
                                , body =
                                    [ Html.button
                                        [ Attr.disabled False
                                        , Html.Events.onClick ()
                                        ]
                                        [ Html.text "Submit" ]
                                    , if model.clicked then
                                        Html.text "Clicked!"
                                      else
                                        Html.text ""
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Submit"
                        |> PagesProgram.ensureViewHas [ Selector.text "Clicked!" ]
                        |> PagesProgram.done
            ]
        , describe "Bug fix: pending effects must not be overwritten"
            [ test "done fails when effects are pending after another interaction" <|
                \() ->
                    -- Bug: clicking a button that triggers an effect, then clicking
                    -- another button before resolving, used to silently drop the effect.
                    -- After fix: done should fail because there's still a pending effect.
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { result = Nothing, other = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    QueueFetch ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "value" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotResult
                                          ]
                                        )

                                    DoOtherThing ->
                                        ( { model | other = True }, [] )

                                    GotResult value ->
                                        ( { model | result = Just value }, [] )
                        , view =
                            \_ model ->
                                { title = "Queue Test"
                                , body =
                                    [ Html.button [ Html.Events.onClick QueueFetch ] [ Html.text "Fetch" ]
                                    , Html.button [ Html.Events.onClick DoOtherThing ] [ Html.text "Other" ]
                                    , case model.result of
                                        Just v ->
                                            Html.text ("Result: " ++ v)

                                        Nothing ->
                                            Html.text "No result"
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Fetch"
                        -- Click another button BEFORE resolving the effect
                        |> PagesProgram.clickButton "Other"
                        -- done should fail: the HTTP effect from "Fetch" is still pending
                        |> PagesProgram.done
                        |> expectFailContaining "pending"
            , test "resolveEffect works after another interaction" <|
                \() ->
                    -- The effect from the first click should survive a second click
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { result = Nothing, other = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    QueueFetch ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "value" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotResult
                                          ]
                                        )

                                    DoOtherThing ->
                                        ( { model | other = True }, [] )

                                    GotResult value ->
                                        ( { model | result = Just value }, [] )
                        , view =
                            \_ model ->
                                { title = "Queue Test"
                                , body =
                                    [ Html.button [ Html.Events.onClick QueueFetch ] [ Html.text "Fetch" ]
                                    , Html.button [ Html.Events.onClick DoOtherThing ] [ Html.text "Other" ]
                                    , case model.result of
                                        Just v ->
                                            Html.text ("Result: " ++ v)

                                        Nothing ->
                                            Html.text "No result"
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Fetch"
                        |> PagesProgram.clickButton "Other"
                        -- Should still be able to resolve the effect from "Fetch"
                        |> PagesProgram.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.example.com/data"
                                (Encode.object [ ( "value", Encode.string "hello" ) ])
                            )
                        |> PagesProgram.ensureViewHas [ Selector.text "Result: hello" ]
                        |> PagesProgram.done
            ]
        , describe "Bug fix: FatalError in data produces clean test failure"
            [ test "done fails cleanly when data BackendTask produces FatalError" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.fail (FatalError.fromString "Database connection failed")
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.done
                        |> expectFailContaining "Database connection failed"
            , test "ensureViewHas fails cleanly when data BackendTask produces FatalError" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.fail (FatalError.fromString "Service unavailable")
                        , init = \_ -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Hello" ]
                        |> PagesProgram.done
                        |> expectFailContaining "Service unavailable"
            ]
        , describe "simulateIncomingPort (elm-program-test style)"
            [ test "can simulate an incoming port message" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { messages = [] }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    GotWebSocket message ->
                                        ( { model | messages = model.messages ++ [ message ] }, [] )
                        , view =
                            \_ model ->
                                { title = "Chat"
                                , body =
                                    [ Html.text
                                        (if List.isEmpty model.messages then
                                            "No messages"

                                         else
                                            String.join ", " model.messages
                                        )
                                    ]
                                }
                        }
                        |> PagesProgram.withSimulatedSubscriptions
                            (\_ ->
                                SimulatedSub.port_ "websocketReceived"
                                    (Decode.string |> Decode.map GotWebSocket)
                            )
                        |> PagesProgram.ensureViewHas [ Selector.text "No messages" ]
                        |> PagesProgram.simulateIncomingPort "websocketReceived"
                            (Encode.string "hello")
                        |> PagesProgram.ensureViewHas [ Selector.text "hello" ]
                        |> PagesProgram.simulateIncomingPort "websocketReceived"
                            (Encode.string "world")
                        |> PagesProgram.ensureViewHas [ Selector.text "hello, world" ]
                        |> PagesProgram.done
            , test "simulateIncomingPort fails when not subscribed to port" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.withSimulatedSubscriptions
                            (\_ -> SimulatedSub.none)
                        |> PagesProgram.simulateIncomingPort "somePort"
                            (Encode.string "data")
                        |> PagesProgram.done
                        |> expectFailContaining "not currently subscribed"
            , test "simulateIncomingPort fails without withSimulatedSubscriptions" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.simulateIncomingPort "somePort"
                            (Encode.string "data")
                        |> PagesProgram.done
                        |> expectFailContaining "withSimulatedSubscriptions"
            , test "subscriptions are model-dependent" <|
                \() ->
                    -- The subscription function re-evaluates with the current
                    -- model. When listening is False, port is not subscribed.
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { listening = False, lastMessage = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    StartListening ->
                                        ( { model | listening = True }, [] )

                                    ReceivedData value ->
                                        ( { model | lastMessage = Just value }, [] )
                        , view =
                            \_ model ->
                                { title = "Listener"
                                , body =
                                    [ if model.listening then
                                        Html.text "Listening"

                                      else
                                        Html.button [ Html.Events.onClick StartListening ]
                                            [ Html.text "Start" ]
                                    , case model.lastMessage of
                                        Just msg ->
                                            Html.text ("Got: " ++ msg)

                                        Nothing ->
                                            Html.text ""
                                    ]
                                }
                        }
                        |> PagesProgram.withSimulatedSubscriptions
                            (\model ->
                                if model.listening then
                                    SimulatedSub.port_ "dataPort"
                                        (Decode.string |> Decode.map ReceivedData)

                                else
                                    SimulatedSub.none
                            )
                        -- Not listening yet, so port should not be subscribed
                        |> PagesProgram.simulateIncomingPort "dataPort"
                            (Encode.string "too early")
                        |> PagesProgram.done
                        |> expectFailContaining "not currently subscribed"
            ]
        , describe "simulateHttpError"
            [ test "simulates a network error on data loading" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/data"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \value -> ( { value = value }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Data", body = [ Html.text model.value ] }
                        }
                        |> PagesProgram.simulateHttpError "GET"
                            "https://api.example.com/data"
                            NetworkError
                        |> PagesProgram.done
                        |> expectFailContaining "NetworkError"
            , test "simulates a timeout on data loading" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/data"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \value -> ( { value = value }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Data", body = [ Html.text model.value ] }
                        }
                        |> PagesProgram.simulateHttpError "GET"
                            "https://api.example.com/data"
                            Timeout
                        |> PagesProgram.done
                        |> expectFailContaining "Timeout"
            ]
        , describe "selectOption"
            [ test "selecting a dropdown option updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { color = "red" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    SelectColor c ->
                                        ( { model | color = c }, [] )
                        , view =
                            \_ model ->
                                { title = "Colors"
                                , body =
                                    [ Html.label [ Attr.for "color-select" ] [ Html.text "Favorite Color" ]
                                    , Html.select
                                        [ Attr.id "color-select"
                                        , Html.Events.onInput SelectColor
                                        ]
                                        [ Html.option [ Attr.value "red" ] [ Html.text "Red" ]
                                        , Html.option [ Attr.value "blue" ] [ Html.text "Blue" ]
                                        , Html.option [ Attr.value "green" ] [ Html.text "Green" ]
                                        ]
                                    , Html.text ("Selected: " ++ model.color)
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Selected: red" ]
                        |> PagesProgram.selectOption "color-select" "Favorite Color" "blue" "Blue"
                        |> PagesProgram.ensureViewHas [ Selector.text "Selected: blue" ]
                        |> PagesProgram.done
            , test "selectOption fails when select element not found" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "No selects" ] }
                        }
                        |> PagesProgram.selectOption "missing" "Missing" "val" "text"
                        |> PagesProgram.done
                        |> expectFailContaining "selectOption"
            ]
        , describe "expectViewHas (terminal assertion)"
            [ test "passes when view has selector" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.expectViewHas [ Selector.text "Hello" ]
            , test "fails when view does not have selector" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.expectViewHas [ Selector.text "Goodbye" ]
                        |> expectFailContaining "Goodbye"
            ]
        , describe "submitFormTo (cross-route form action)"
            [ test "submitFormTo fails gracefully without startPlatform" <|
                \() ->
                    -- submitFormTo requires startPlatform (which provides
                    -- onFormSubmit). With plain start, it errors clearly.
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.submitFormTo "/logout"
                            { formId = "logout-form", fields = [] }
                        |> PagesProgram.done
                        |> expectFailContaining "Form submission is only supported"
            ]
        , describe "cookie jar"
            [ test "CookieJar.empty has no cookies" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.get "anything"
                        |> Expect.equal Nothing
            , test "CookieJar.set adds a cookie" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.set "theme" "dark"
                        |> CookieJar.get "theme"
                        |> Expect.equal (Just "dark")
            , test "CookieJar.fromSetCookieHeaders parses Set-Cookie headers" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.applySetCookieHeaders
                            [ "session=abc123; Path=/; HttpOnly"
                            , "theme=dark; Path=/"
                            ]
                        |> CookieJar.get "session"
                        |> Expect.equal (Just "abc123")
            , test "CookieJar.toCookieDict produces dict for request" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.set "a" "1"
                        |> CookieJar.set "b" "2"
                        |> CookieJar.toDict
                        |> Dict.get "a"
                        |> Expect.equal (Just "1")
            , test "Set-Cookie with multiple attributes parsed correctly" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.applySetCookieHeaders
                            [ "token=xyz789; Path=/; Domain=.example.com; Secure; HttpOnly; SameSite=Strict; Max-Age=3600" ]
                        |> CookieJar.get "token"
                        |> Expect.equal (Just "xyz789")
            , test "multiple Set-Cookie headers accumulate" <|
                \() ->
                    let
                        jar =
                            CookieJar.empty
                                |> CookieJar.applySetCookieHeaders
                                    [ "a=1; Path=/"
                                    , "b=2; Path=/"
                                    , "c=3; Path=/"
                                    ]
                    in
                    ( CookieJar.get "a" jar
                    , CookieJar.get "b" jar
                    , CookieJar.get "c" jar
                    )
                        |> Expect.equal ( Just "1", Just "2", Just "3" )
            , test "Set-Cookie overwrites existing cookie" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.set "theme" "light"
                        |> CookieJar.applySetCookieHeaders
                            [ "theme=dark; Path=/" ]
                        |> CookieJar.get "theme"
                        |> Expect.equal (Just "dark")
            , test "URL-encoded cookie values are decoded" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.applySetCookieHeaders
                            [ "data=hello%20world; Path=/" ]
                        |> CookieJar.get "data"
                        |> Expect.equal (Just "hello world")
            ]
        , describe "startWithEffects (custom Effect type simulation)"
            [ test "user-defined effects are converted to BackendTasks" <|
                \() ->
                    -- Users have a custom Effect type. They provide a function
                    -- to convert it to BackendTasks the framework can handle.
                    PagesProgram.startWithEffects
                        (\effect ->
                            case effect of
                                MyEffectNone ->
                                    []

                                MyEffectBatch effects ->
                                    List.concatMap
                                        (\e ->
                                            case e of
                                                MyFetchApi toMsg ->
                                                    [ BackendTask.Http.getJson
                                                        "https://api.example.com/data"
                                                        (Decode.field "name" Decode.string)
                                                        |> BackendTask.allowFatal
                                                        |> BackendTask.map toMsg
                                                    ]

                                                _ ->
                                                    []
                                        )
                                        effects

                                MyFetchApi toMsg ->
                                    [ BackendTask.Http.getJson
                                        "https://api.example.com/data"
                                        (Decode.field "name" Decode.string)
                                        |> BackendTask.allowFatal
                                        |> BackendTask.map toMsg
                                    ]
                        )
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { name = Nothing }, MyEffectNone )
                        , update =
                            \msg model ->
                                case msg of
                                    LoadName ->
                                        ( model, MyFetchApi GotName )

                                    GotName n ->
                                        ( { model | name = Just n }, MyEffectNone )
                        , view =
                            \_ model ->
                                { title = "Custom Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick LoadName ] [ Html.text "Load" ]
                                    , case model.name of
                                        Just n ->
                                            Html.text ("Name: " ++ n)

                                        Nothing ->
                                            Html.text "No name"
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "No name" ]
                        |> PagesProgram.clickButton "Load"
                        |> PagesProgram.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.example.com/data"
                                (Encode.object [ ( "name", Encode.string "Alice" ) ])
                            )
                        |> PagesProgram.ensureViewHas [ Selector.text "Name: Alice" ]
                        |> PagesProgram.done
            ]
        , describe "effect tracking"
            [ test "done reports count of unresolved effects" <|
                \() ->
                    -- When there are pending effects at the end, done should
                    -- report how many AND describe what's pending
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { value = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    TriggerEffect ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "v" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotEffectResult
                                          ]
                                        )

                                    GotEffectResult v ->
                                        ( { model | value = Just v }, [] )
                        , view =
                            \_ model ->
                                { title = "Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ]
                                    , case model.value of
                                        Just v ->
                                            Html.text ("Got: " ++ v)

                                        Nothing ->
                                            Html.text "Waiting"
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.done
                        |> expectFailContaining "1 pending"
            , test "multiple effects from different interactions all tracked" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { value = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    TriggerEffect ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "v" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotEffectResult
                                          ]
                                        )

                                    GotEffectResult v ->
                                        ( { model | value = Just v }, [] )
                        , view =
                            \_ model ->
                                { title = "Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.done
                        |> expectFailContaining "2 pending"
            , test "done describes what effects are pending" <|
                \() ->
                    -- done should include the URLs of pending HTTP requests
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { value = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    TriggerEffect ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "v" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotEffectResult
                                          ]
                                        )

                                    GotEffectResult v ->
                                        ( { model | value = Just v }, [] )
                        , view =
                            \_ model ->
                                { title = "Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ] ]
                                }
                        }
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.done
                        |> expectFailContaining "api.example.com"
            ]
        , describe "expectModel"
            [ test "can inspect the model directly" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { count = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Increment ->
                                        ( { model | count = model.count + 1 }, [] )

                                    Decrement ->
                                        ( { model | count = model.count - 1 }, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    , Html.text (String.fromInt model.count)
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.expectModel
                            (\model -> model.count |> Expect.equal 3)
            , test "expectModel fails with useful message" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { count = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Increment ->
                                        ( { model | count = model.count + 1 }, [] )

                                    Decrement ->
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    , Html.text (String.fromInt model.count)
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.expectModel
                            (\model -> model.count |> Expect.equal 99)
                        |> expectFailContaining "Expect.equal"
            ]
        , describe "textarea support"
            [ test "fillIn works with textarea" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { content = "" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    UpdateContent c ->
                                        ( { model | content = c }, [] )
                        , view =
                            \_ model ->
                                { title = "Editor"
                                , body =
                                    [ Html.textarea
                                        [ Attr.id "editor"
                                        , Attr.value model.content
                                        , Html.Events.onInput UpdateContent
                                        ]
                                        []
                                    , Html.text ("Content: " ++ model.content)
                                    ]
                                }
                        }
                        |> PagesProgram.fillIn "editor" "editor" "Hello textarea!"
                        |> PagesProgram.ensureViewHas [ Selector.text "Content: Hello textarea!" ]
                        |> PagesProgram.done
            ]
        ]


type ContentMsg
    = UpdateContent String


type CounterMsg
    = Increment
    | Decrement


type SearchMsg
    = UpdateQuery String


type CheckMsg
    = ToggleAgreed Bool


type StarsMsg
    = FetchStars
    | GotStars Int


type QueueMsg
    = QueueFetch
    | DoOtherThing
    | GotResult String


type WebSocketMsg
    = GotWebSocket String


type ListenerMsg
    = StartListening
    | ReceivedData String


type SelectMsg
    = SelectColor String


type EffectTrackMsg
    = TriggerEffect
    | GotEffectResult String


type MyEffect msg
    = MyEffectNone
    | MyEffectBatch (List (MyEffect msg))
    | MyFetchApi (String -> msg)


type CustomEffectMsg
    = LoadName
    | GotName String




{-| Assert that an Expectation is a failure containing the given substring.
-}
expectFailContaining : String -> Expectation -> Expectation
expectFailContaining substring expectation =
    case Test.Runner.getFailureReason expectation of
        Nothing ->
            Expect.fail
                ("Expected test to fail with message containing \""
                    ++ substring
                    ++ "\", but it passed."
                )

        Just { description } ->
            if String.contains substring description then
                Expect.pass

            else
                Expect.fail
                    ("Expected failure message to contain \""
                        ++ substring
                        ++ "\", but the actual message was:\n\n"
                        ++ description
                    )
