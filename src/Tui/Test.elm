module Tui.Test exposing
    ( TuiTest
    , start, startWithContext
    , pressKey, pressKeyWith, resize
    , sendMsg
    , resolveEffect
    , ensureView, ensureViewHas, ensureViewDoesNotHave
    , expectRunning, expectExit, expectExitWith
    )

{-| Write pure tests for TUI scripts. No terminal, no I/O — just regular
Elm tests.

Effects returned by `update` are tracked and can be resolved using
[`resolveEffect`](#resolveEffect) with the full `Test.BackendTask` API,
or directly with [`sendMsg`](#sendMsg).

    import Expect
    import Json.Encode as Encode
    import Test exposing (test)
    import Test.BackendTask as BackendTaskTest
    import Tui
    import Tui.Test as TuiTest

    test "fetches stars on Enter" <|
        \() ->
            TuiTest.start
                { data = ()
                , init = Stars.init
                , update = Stars.update
                , view = Stars.view
                , subscriptions = Stars.subscriptions
                }
                |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                |> TuiTest.ensureViewHas "Loading..."
                |> TuiTest.resolveEffect
                    (BackendTaskTest.simulateHttpGet
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Encode.object [ ( "stargazers_count", Encode.int 1234 ) ])
                    )
                |> TuiTest.ensureViewHas "Stars: 1234"
                |> TuiTest.expectRunning

@docs TuiTest

@docs start, startWithContext

@docs pressKey, pressKeyWith, resize

@docs sendMsg

@docs resolveEffect

@docs ensureView, ensureViewHas, ensureViewDoesNotHave

@docs expectRunning, expectExit, expectExitWith

-}

import BackendTask exposing (BackendTask)
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Test.BackendTask.Internal as BackendTaskTest
import Test.Runner
import Tui exposing (Context, KeyEvent, Screen)
import Tui.Effect as Effect exposing (Effect)
import Tui.Sub as Sub exposing (Sub)


{-| An in-progress TUI test. Thread this through the pipeline to simulate
events and assert on screen output.
-}
type TuiTest model msg
    = TuiTest (State model msg)


type alias State model msg =
    { model : model
    , update : msg -> model -> ( model, Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Sub msg
    , context : Context
    , pendingEffects : List (BackendTask FatalError msg)
    , exited : Maybe Int
    , error : Maybe String
    }


{-| Start a TUI test. Provide the same config record you pass to `Script.tui`,
but with `data` already resolved (not a `BackendTask`).

    TuiTest.start
        { data = { files = [ "Main.elm" ] }
        , init = MyTui.init
        , update = MyTui.update
        , view = MyTui.view
        , subscriptions = MyTui.subscriptions
        }

-}
start :
    { data : data
    , init : data -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Sub msg
    }
    -> TuiTest model msg
start config =
    startWithContext { width = 80, height = 24 } config


{-| Like `start` but with a custom terminal size.

    TuiTest.startWithContext { width = 120, height = 40 }
        { data = (), ... }

-}
startWithContext :
    Context
    ->
        { data : data
        , init : data -> ( model, Effect msg )
        , update : msg -> model -> ( model, Effect msg )
        , view : Context -> model -> Screen
        , subscriptions : model -> Sub msg
        }
    -> TuiTest model msg
startWithContext context config =
    let
        ( initialModel, initialEffect ) =
            config.init config.data
    in
    TuiTest
        { model = initialModel
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        , context = context
        , pendingEffects = extractBackendTasks initialEffect
        , exited = checkForExit initialEffect
        , error = Nothing
        }



-- SIMULATING EVENTS


{-| Simulate pressing a character key with no modifiers.

    test |> TuiTest.pressKey 'j'

-}
pressKey : Char -> TuiTest model msg -> TuiTest model msg
pressKey char =
    pressKeyWith { key = Tui.Character char, modifiers = [] }


{-| Simulate pressing any key, including special keys and modifiers.

    test |> TuiTest.pressKeyWith { key = Tui.Arrow Tui.Down, modifiers = [] }
    test |> TuiTest.pressKeyWith { key = Tui.Character 's', modifiers = [ Tui.Ctrl ] }

-}
pressKeyWith : KeyEvent -> TuiTest model msg -> TuiTest model msg
pressKeyWith keyEvent (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "pressKey called after TUI exited" }

        ( Nothing, Nothing ) ->
            let
                sub =
                    state.subscriptions state.model
            in
            case Sub.routeEvent sub (Sub.RawKeyPress keyEvent) of
                Just msg ->
                    applyMsg msg (TuiTest state)

                Nothing ->
                    TuiTest state


{-| Simulate a terminal resize. The framework handles resize automatically —
this just updates the `Context` that `view` receives. No user message is sent.
-}
resize : { width : Int, height : Int } -> TuiTest model msg -> TuiTest model msg
resize size (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "resize called after TUI exited" }

        ( Nothing, Nothing ) ->
            TuiTest { state | context = size }


{-| Send a message directly through `update`. Useful for simulating
`BackendTask` results without needing the full simulation infrastructure.

    test
        |> TuiTest.pressKey 's'
        |> TuiTest.sendMsg (StagingComplete "file.elm")
        |> TuiTest.ensureViewHas "staged"

-}
sendMsg : msg -> TuiTest model msg -> TuiTest model msg
sendMsg msg =
    applyMsg msg



-- BACKENDTASK SIMULATION


{-| Resolve a pending `BackendTask` effect using the full `Test.BackendTask`
API. The next pending `BackendTask` (from the most recent `Effect.perform` or
`Effect.attempt`) is run through `Test.BackendTask.fromBackendTask`, then your
simulation function is applied, and the resolved result is fed through `update`.

    import Test.BackendTask as BackendTaskTest

    test "fetches stars on Enter" <|
        \() ->
            starsTest
                |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                |> TuiTest.resolveEffect
                    (BackendTaskTest.simulateHttpGet
                        "https://api.github.com/repos/elm/core"
                        (Encode.object [ ( "stargazers_count", Encode.int 7500 ) ])
                    )
                |> TuiTest.ensureViewHas "Stars: 7500"

You can chain multiple simulations for BackendTasks that require more than one:

    |> TuiTest.resolveEffect
        (BackendTaskTest.simulateCommand "git" "M src/Main.elm"
            >> BackendTaskTest.simulateCommand "git" "main"
        )

-}
resolveEffect :
    (BackendTaskTest.BackendTaskTest msg -> BackendTaskTest.BackendTaskTest msg)
    -> TuiTest model msg
    -> TuiTest model msg
resolveEffect simulate =
    resolveNextEffect
        (\bt ->
            bt
                |> BackendTaskTest.fromBackendTask
                |> simulate
        )



-- SCREEN ASSERTIONS


{-| Assert on the current screen content using a custom assertion function.
The function receives the plain text content (no styling) of the rendered
screen.

    test
        |> TuiTest.ensureView
            (\text ->
                if String.contains "Error" text then
                    Expect.fail "Should not show error"

                else
                    Expect.pass
            )

-}
ensureView : (String -> Expectation) -> TuiTest model msg -> TuiTest model msg
ensureView assertion (TuiTest state) =
    case state.error of
        Just _ ->
            TuiTest state

        Nothing ->
            let
                screenText =
                    Tui.toString (state.view state.context state.model)

                result =
                    assertion screenText
            in
            case getFailureMessage result of
                Just msg ->
                    TuiTest { state | error = Just ("ensureView failed:\n" ++ msg) }

                Nothing ->
                    TuiTest state


{-| Assert that the current screen contains the given text.

    test |> TuiTest.ensureViewHas "Count: 0"

-}
ensureViewHas : String -> TuiTest model msg -> TuiTest model msg
ensureViewHas needle (TuiTest state) =
    case state.error of
        Just _ ->
            TuiTest state

        Nothing ->
            let
                screenText =
                    Tui.toString (state.view state.context state.model)
            in
            if String.contains needle screenText then
                TuiTest state

            else
                TuiTest
                    { state
                        | error =
                            Just
                                ("ensureViewHas: expected screen to contain:\n\n    \""
                                    ++ needle
                                    ++ "\"\n\nbut the screen was:\n\n"
                                    ++ indentScreenText screenText
                                )
                    }


{-| Assert that the current screen does NOT contain the given text.
-}
ensureViewDoesNotHave : String -> TuiTest model msg -> TuiTest model msg
ensureViewDoesNotHave needle (TuiTest state) =
    case state.error of
        Just _ ->
            TuiTest state

        Nothing ->
            let
                screenText =
                    Tui.toString (state.view state.context state.model)
            in
            if String.contains needle screenText then
                TuiTest
                    { state
                        | error =
                            Just
                                ("ensureViewDoesNotHave: expected screen NOT to contain:\n\n    \""
                                    ++ needle
                                    ++ "\"\n\nbut the screen was:\n\n"
                                    ++ indentScreenText screenText
                                )
                    }

            else
                TuiTest state



-- TERMINAL ASSERTIONS


{-| Assert that the TUI is still running (has not exited).
-}
expectRunning : TuiTest model msg -> Expectation
expectRunning (TuiTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case state.exited of
                Nothing ->
                    Expect.pass

                Just code ->
                    Expect.fail ("Expected TUI to be running, but it exited with code " ++ String.fromInt code)


{-| Assert that the TUI exited with code 0.
-}
expectExit : TuiTest model msg -> Expectation
expectExit (TuiTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case state.exited of
                Just 0 ->
                    Expect.pass

                Just code ->
                    Expect.fail ("Expected exit code 0, but got " ++ String.fromInt code)

                Nothing ->
                    Expect.fail "Expected TUI to exit, but it is still running"


{-| Assert that the TUI exited with a specific exit code.
-}
expectExitWith : Int -> TuiTest model msg -> Expectation
expectExitWith expectedCode (TuiTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case state.exited of
                Just code ->
                    if code == expectedCode then
                        Expect.pass

                    else
                        Expect.fail ("Expected exit code " ++ String.fromInt expectedCode ++ ", but got " ++ String.fromInt code)

                Nothing ->
                    Expect.fail ("Expected TUI to exit with code " ++ String.fromInt expectedCode ++ ", but it is still running")



-- HELPERS


applyMsg : msg -> TuiTest model msg -> TuiTest model msg
applyMsg msg (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest state

        ( Nothing, Nothing ) ->
            let
                ( newModel, effect ) =
                    state.update msg state.model
            in
            TuiTest
                { state
                    | model = newModel
                    , pendingEffects = extractBackendTasks effect
                    , exited = checkForExit effect
                }


{-| Resolve the next pending BackendTask effect using a simulation function.
The simulation function takes the raw BackendTask and returns a BackendTaskTest
that has been configured with the appropriate simulation.
-}
resolveNextEffect :
    (BackendTask FatalError msg -> BackendTaskTest.BackendTaskTest msg)
    -> TuiTest model msg
    -> TuiTest model msg
resolveNextEffect simulate (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "simulateEffect called after TUI exited" }

        ( Nothing, Nothing ) ->
            case state.pendingEffects of
                [] ->
                    TuiTest
                        { state
                            | error =
                                Just "No pending BackendTask effect to resolve. Did you forget to trigger an action (e.g., press Enter) before simulating?"
                        }

                bt :: rest ->
                    let
                        testResult =
                            simulate bt
                                |> BackendTaskTest.toResult
                    in
                    case testResult of
                        Ok msg ->
                            let
                                ( newModel, newEffect ) =
                                    state.update msg state.model
                            in
                            TuiTest
                                { state
                                    | model = newModel
                                    , pendingEffects = rest ++ extractBackendTasks newEffect
                                    , exited = checkForExit newEffect
                                }

                        Err errMsg ->
                            TuiTest { state | error = Just ("Effect resolution failed: " ++ errMsg) }


extractBackendTasks : Effect msg -> List (BackendTask FatalError msg)
extractBackendTasks effect =
    case effect of
        Effect.None ->
            []

        Effect.Batch effects ->
            List.concatMap extractBackendTasks effects

        Effect.RunBackendTask bt ->
            [ bt ]

        Effect.SuspendBackendTask bt ->
            [ bt ]

        Effect.Exit ->
            []

        Effect.ExitWithCode _ ->
            []


checkForExit : Effect msg -> Maybe Int
checkForExit effect =
    case effect of
        Effect.Exit ->
            Just 0

        Effect.ExitWithCode code ->
            Just code

        Effect.Batch effects ->
            effects
                |> List.filterMap checkForExit
                |> List.head

        _ ->
            Nothing


indentScreenText : String -> String
indentScreenText screenText =
    screenText
        |> String.lines
        |> List.map (\line -> "    " ++ line)
        |> String.join "\n"


getFailureMessage : Expectation -> Maybe String
getFailureMessage expectation =
    case Test.Runner.getFailureReason expectation of
        Just reason ->
            Just reason.description

        Nothing ->
            Nothing
