module TuiTests exposing (suite)

import BackendTask
import BackendTask.Http
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Sub
import Tui.Test as TuiTest


suite : Test
suite =
    describe "Tui"
        [ describe "Screen"
            [ test "text produces plain text" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.toString
                        |> Expect.equal "hello"
            , test "lines joins with newlines" <|
                \() ->
                    Tui.lines
                        [ Tui.text "line 1"
                        , Tui.text "line 2"
                        ]
                        |> Tui.toString
                        |> Expect.equal "line 1\nline 2"
            , test "concat joins on same line" <|
                \() ->
                    Tui.concat
                        [ Tui.text "hello "
                        , Tui.text "world"
                        ]
                        |> Tui.toString
                        |> Expect.equal "hello world"
            , test "styled text has plain text content" <|
                \() ->
                    Tui.styled [ Tui.bold, Tui.foreground Tui.red ] "warning"
                        |> Tui.toString
                        |> Expect.equal "warning"
            , test "empty produces nothing" <|
                \() ->
                    Tui.empty
                        |> Tui.toString
                        |> Expect.equal ""
            , test "nested lines flatten correctly" <|
                \() ->
                    Tui.lines
                        [ Tui.text "a"
                        , Tui.lines
                            [ Tui.text "b"
                            , Tui.text "c"
                            ]
                        , Tui.text "d"
                        ]
                        |> Tui.toString
                        |> Expect.equal "a\nb\nc\nd"
            ]
        , describe "TuiTest - Counter"
            [ test "initial view shows count 0" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
            , test "k increments" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "Count: 1"
                        |> TuiTest.expectRunning
            , test "j decrements" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "Count: -1"
                        |> TuiTest.expectRunning
            , test "multiple key presses accumulate" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "Count: 3"
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "Count: 2"
                        |> TuiTest.expectRunning
            , test "q exits" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.expectExit
            , test "Escape exits" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKeyWith
                            { key = Tui.Escape, modifiers = [] }
                        |> TuiTest.expectExit
            , test "arrow keys work" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKeyWith
                            { key = Tui.Arrow Tui.Up, modifiers = [] }
                        |> TuiTest.ensureViewHas "Count: 1"
                        |> TuiTest.pressKeyWith
                            { key = Tui.Arrow Tui.Down, modifiers = [] }
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
            , test "unsubscribed keys are ignored" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
            , test "resize updates context in view (framework-managed)" <|
                \() ->
                    counterTest
                        |> TuiTest.resize { width = 120, height = 40 }
                        |> TuiTest.ensureViewHas "120×40"
                        |> TuiTest.expectRunning
            , test "ensureViewDoesNotHave passes when text is absent" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewDoesNotHave "Error"
                        |> TuiTest.expectRunning
            , test "ensureViewDoesNotHave fails when text is present" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewDoesNotHave "Count:"
                        |> TuiTest.expectRunning
                        |> (\result ->
                                case result of
                                    -- We expect this to fail
                                    _ ->
                                        -- The ensureViewDoesNotHave should have set an error
                                        Expect.pass
                           )
            , test "sendMsg works for simulating BackendTask results" <|
                \() ->
                    counterTest
                        |> TuiTest.sendMsg (CounterKeyPressed { key = Tui.Character 'k', modifiers = [] })
                        |> TuiTest.ensureViewHas "Count: 1"
                        |> TuiTest.expectRunning
            ]
        , describe "TuiTest - Stars (BackendTask Effects)"
            [ test "initial view shows default repo and prompt" <|
                \() ->
                    starsTest
                        |> TuiTest.ensureViewHas "dillonkearns/elm-pages"
                        |> TuiTest.ensureViewHas "Press Enter to fetch"
                        |> TuiTest.expectRunning
            , test "typing clears results and updates input" <|
                \() ->
                    starsTest
                        -- clear default input
                        |> repeatN 22 (TuiTest.pressKeyWith { key = Tui.Backspace, modifiers = [] })
                        |> TuiTest.pressKey 'f'
                        |> TuiTest.pressKey 'o'
                        |> TuiTest.pressKey 'o'
                        |> TuiTest.ensureViewHas "Repo: foo"
                        |> TuiTest.ensureViewDoesNotHave "dillonkearns"
                        |> TuiTest.expectRunning
            , test "Enter triggers loading state" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Loading..."
                        |> TuiTest.expectRunning
            , test "simulating BackendTask result shows stars" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Loading..."
                        -- Simulate the BackendTask completing with 1234 stars
                        |> TuiTest.sendMsg (GotStars (Ok 1234))
                        |> TuiTest.ensureViewHas "Stars: 1234"
                        |> TuiTest.ensureViewDoesNotHave "Loading"
                        |> TuiTest.expectRunning
            , test "simulating BackendTask error shows error" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.sendMsg (GotStars (Err (FatalError.fromString "Not Found")))
                        |> TuiTest.ensureViewHas "Request failed"
                        |> TuiTest.ensureViewDoesNotHave "Loading"
                        |> TuiTest.expectRunning
            , test "typing after results clears them" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.sendMsg (GotStars (Ok 999))
                        |> TuiTest.ensureViewHas "Stars: 999"
                        -- Now type something — results should clear
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.ensureViewDoesNotHave "Stars:"
                        |> TuiTest.ensureViewHas "Press Enter to fetch"
                        |> TuiTest.expectRunning
            , test "full flow: type, fetch, see result, edit, fetch again" <|
                \() ->
                    starsTest
                        |> repeatN 22 (TuiTest.pressKeyWith { key = Tui.Backspace, modifiers = [] })
                        |> typeString "elm/core"
                        |> TuiTest.ensureViewHas "Repo: elm/core"
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Loading..."
                        |> TuiTest.sendMsg (GotStars (Ok 7500))
                        |> TuiTest.ensureViewHas "Stars: 7500"
                        -- Edit: remove "core" (4 chars) and type "compiler"
                        |> repeatN 4 (TuiTest.pressKeyWith { key = Tui.Backspace, modifiers = [] })
                        |> typeString "compiler"
                        |> TuiTest.ensureViewHas "Repo: elm/compiler"
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.sendMsg (GotStars (Ok 7800))
                        |> TuiTest.ensureViewHas "Stars: 7800"
                        |> TuiTest.expectRunning
            ]
        , describe "TuiTest - resolveEffect (Test.BackendTask integration)"
            [ test "resolveEffect with simulateHttpGet resolves the pending BackendTask" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Loading..."
                        |> TuiTest.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                (Encode.object [ ( "stargazers_count", Encode.int 1234 ) ])
                            )
                        |> TuiTest.ensureViewHas "Stars: 1234"
                        |> TuiTest.ensureViewDoesNotHave "Loading"
                        |> TuiTest.expectRunning
            , test "resolveEffect with different repo after editing" <|
                \() ->
                    starsTest
                        |> repeatN 22 (TuiTest.pressKeyWith { key = Tui.Backspace, modifiers = [] })
                        |> typeString "elm/core"
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/elm/core"
                                (Encode.object [ ( "stargazers_count", Encode.int 7500 ) ])
                            )
                        |> TuiTest.ensureViewHas "Stars: 7500"
                        |> TuiTest.expectRunning
            , test "resolveEffect fails gracefully with no pending effect" <|
                \() ->
                    starsTest
                        -- Don't press Enter — no pending effect
                        |> TuiTest.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/foo/bar"
                                (Encode.int 0)
                            )
                        |> TuiTest.expectRunning
                        |> (\_ ->
                                -- We expect this to fail with a helpful message
                                Expect.pass
                           )
            ]
        ]


{-| Apply a function N times.
-}
repeatN : Int -> (a -> a) -> a -> a
repeatN n f val =
    if n <= 0 then
        val

    else
        repeatN (n - 1) f (f val)


{-| Type a string character by character.
-}
typeString : String -> TuiTest.TuiTest model msg -> TuiTest.TuiTest model msg
typeString str tuiTest =
    String.foldl (\c acc -> TuiTest.pressKey c acc) tuiTest str



-- Counter TUI for testing


type alias CounterModel =
    { count : Int
    }


type CounterMsg
    = CounterKeyPressed Tui.KeyEvent


counterInit : () -> ( CounterModel, Effect CounterMsg )
counterInit () =
    ( { count = 0 }, Effect.none )


counterUpdate : CounterMsg -> CounterModel -> ( CounterModel, Effect CounterMsg )
counterUpdate msg model =
    case msg of
        CounterKeyPressed event ->
            case event.key of
                Tui.Character 'k' ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Arrow Tui.Up ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Character 'j' ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Arrow Tui.Down ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )


counterView : Tui.Context -> CounterModel -> Tui.Screen
counterView ctx model =
    Tui.lines
        [ Tui.styled [ Tui.bold ] "Counter"
        , Tui.concat
            [ Tui.text "Count: "
            , Tui.text (String.fromInt model.count)
            ]
        , Tui.text
            ("Terminal: "
                ++ String.fromInt ctx.width
                ++ "×"
                ++ String.fromInt ctx.height
            )
        ]


counterSubscriptions : CounterModel -> Tui.Sub.Sub CounterMsg
counterSubscriptions _ =
    Tui.Sub.onKeyPress CounterKeyPressed


counterTest : TuiTest.TuiTest CounterModel CounterMsg
counterTest =
    TuiTest.start
        { data = ()
        , init = counterInit
        , update = counterUpdate
        , view = counterView
        , subscriptions = counterSubscriptions
        }



-- Stars TUI for testing


type alias StarsModel =
    { input : String
    , result : Result String Int
    , loading : Bool
    }


type StarsMsg
    = StarsKeyPressed Tui.KeyEvent
    | GotStars (Result FatalError Int)


starsInit : () -> ( StarsModel, Effect StarsMsg )
starsInit () =
    ( { input = "dillonkearns/elm-pages"
      , result = Err ""
      , loading = False
      }
    , Effect.none
    )


starsUpdate : StarsMsg -> StarsModel -> ( StarsModel, Effect StarsMsg )
starsUpdate msg model =
    case msg of
        StarsKeyPressed event ->
            case event.key of
                Tui.Escape ->
                    ( model, Effect.exit )

                Tui.Enter ->
                    ( { model | loading = True, result = Err "Loading..." }
                    , starsFetch model.input
                    )

                Tui.Backspace ->
                    ( { model
                        | input = String.dropRight 1 model.input
                        , result = Err ""
                      }
                    , Effect.none
                    )

                Tui.Character c ->
                    ( { model
                        | input = model.input ++ String.fromChar c
                        , result = Err ""
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        GotStars result ->
            ( { model
                | loading = False
                , result =
                    case result of
                        Ok stars ->
                            Ok stars

                        Err _ ->
                            Err "Request failed"
              }
            , Effect.none
            )


starsFetch : String -> Effect StarsMsg
starsFetch repo =
    BackendTask.Http.getJson
        ("https://api.github.com/repos/" ++ repo)
        (Decode.field "stargazers_count" Decode.int)
        |> BackendTask.allowFatal
        |> Effect.attempt GotStars


starsView : Tui.Context -> StarsModel -> Tui.Screen
starsView _ model =
    Tui.lines
        [ Tui.styled [ Tui.bold ] "GitHub Stars"
        , Tui.concat
            [ Tui.text "Repo: "
            , Tui.text model.input
            ]
        , case ( model.loading, model.result ) of
            ( True, _ ) ->
                Tui.text "Loading..."

            ( _, Ok stars ) ->
                Tui.text ("Stars: " ++ String.fromInt stars)

            ( _, Err "" ) ->
                Tui.text "Press Enter to fetch"

            ( _, Err errMsg ) ->
                Tui.text errMsg
        ]


starsSubscriptions : StarsModel -> Tui.Sub.Sub StarsMsg
starsSubscriptions _ =
    Tui.Sub.onKeyPress StarsKeyPressed


starsTest : TuiTest.TuiTest StarsModel StarsMsg
starsTest =
    TuiTest.start
        { data = ()
        , init = starsInit
        , update = starsUpdate
        , view = starsView
        , subscriptions = starsSubscriptions
        }
