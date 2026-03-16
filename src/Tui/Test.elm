module Tui.Test exposing
    ( TuiTest
    , start, startWithContext
    , pressKey, pressKeyWith, resize
    , sendMsg
    , ensureView, ensureViewHas, ensureViewDoesNotHave
    , expectRunning, expectExit, expectExitWith
    )

{-| Write pure tests for TUI scripts. No terminal, no I/O — just regular
Elm tests.

    import Expect
    import Test exposing (test)
    import Tui
    import Tui.Test as TuiTest

    test "counter increments on k" <|
        \() ->
            TuiTest.start
                { data = ()
                , init = Counter.init
                , update = Counter.update
                , view = Counter.view
                , subscriptions = Counter.subscriptions
                }
                |> TuiTest.ensureViewHas "Count: 0"
                |> TuiTest.pressKey 'k'
                |> TuiTest.ensureViewHas "Count: 1"
                |> TuiTest.pressKey 'q'
                |> TuiTest.expectExit

@docs TuiTest

@docs start, startWithContext

@docs pressKey, pressKeyWith, resize

@docs sendMsg

@docs ensureView, ensureViewHas, ensureViewDoesNotHave

@docs expectRunning, expectExit, expectExitWith

-}

import Expect exposing (Expectation)
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


{-| Simulate a terminal resize.
-}
resize : { width : Int, height : Int } -> TuiTest model msg -> TuiTest model msg
resize size (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "resize called after TUI exited" }

        ( Nothing, Nothing ) ->
            let
                newState =
                    { state | context = size }

                sub =
                    state.subscriptions state.model
            in
            case Sub.routeEvent sub (Sub.RawResize size) of
                Just msg ->
                    applyMsg msg (TuiTest newState)

                Nothing ->
                    TuiTest newState


{-| Send a message directly through `update`. Useful for simulating
`BackendTask` results without needing the actual `BackendTask` infrastructure.

    test
        |> TuiTest.pressKey 's'  -- triggers a BackendTask
        |> TuiTest.sendMsg (StagingComplete "file.elm")  -- simulate it completing
        |> TuiTest.ensureViewHas "staged"

-}
sendMsg : msg -> TuiTest model msg -> TuiTest model msg
sendMsg msg =
    applyMsg msg



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
                    , exited = checkForExit effect
                }


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


{-| Extract failure message from an Expectation, if it failed.
Uses Test.Runner.getFailureReason from elm-explorations/test.
-}
getFailureMessage : Expectation -> Maybe String
getFailureMessage expectation =
    case Test.Runner.getFailureReason expectation of
        Just reason ->
            Just reason.description

        Nothing ->
            Nothing
