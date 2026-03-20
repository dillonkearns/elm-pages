module Tui.Test exposing
    ( TuiTest
    , start, startWithContext
    , pressKey, pressKeyWith, paste, resize
    , click, clickText, scrollDown, scrollUp
    , sendMsg
    , BackendTaskSimulator, resolveEffect
    , ensureView, ensureViewHas, ensureViewDoesNotHave
    , expectRunning, expectExit, expectExitWith
    , Snapshot, toSnapshots, withModelToString
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

@docs pressKey, pressKeyWith, paste, resize

@docs click, clickText, scrollDown, scrollUp

@docs sendMsg

@docs BackendTaskSimulator, resolveEffect

@docs ensureView, ensureViewHas, ensureViewDoesNotHave

@docs expectRunning, expectExit, expectExitWith


## Snapshots

@docs Snapshot, toSnapshots, withModelToString

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
    , snapshots : List Snapshot
    , modelToString : Maybe (model -> String)
    }


{-| A snapshot of the TUI state at a point in the test pipeline. Used by
[`toSnapshots`](#toSnapshots) for the interactive test stepper.

`screen` is the `Tui.Screen` value (preserving styling), not a plain string.
Use `Tui.toString` to get plain text, or render it through the TUI pipeline
for styled output.

`rerender` lets you render the view at a different terminal size than the
one used during the test.

-}
type alias Snapshot =
    { label : String
    , screen : Screen
    , rerender : Context -> Screen
    , hasPendingEffects : Bool
    , modelState : Maybe String
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
    startWithContext { width = 80, height = 24, colorProfile = Tui.TrueColor } config


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

        ( modelWithContext, contextEffect ) =
            case Sub.routeEvent (config.subscriptions initialModel) (Sub.RawContext { width = context.width, height = context.height }) of
                Just msg ->
                    config.update msg initialModel

                Nothing ->
                    ( initialModel, Effect.none )

        combinedEffect : Effect msg
        combinedEffect =
            Effect.batch [ initialEffect, contextEffect ]

        pendingEffects : List (BackendTask FatalError msg)
        pendingEffects =
            extractBackendTasks combinedEffect
    in
    TuiTest
        { model = modelWithContext
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        , context = context
        , pendingEffects = pendingEffects
        , exited = checkForExit combinedEffect
        , error = Nothing
        , snapshots =
            [ { label = "init"
              , screen = config.view context modelWithContext
              , rerender = \ctx -> config.view ctx modelWithContext
              , hasPendingEffects = not (List.isEmpty pendingEffects)
              , modelState = Nothing
              }
            ]
        , modelToString = Nothing
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
                sub : Sub msg
                sub =
                    state.subscriptions state.model
            in
            case Sub.routeEvent sub (Sub.RawKeyPress keyEvent) of
                Just msg ->
                    applyMsg (keyEventLabel keyEvent) msg (TuiTest state)

                Nothing ->
                    TuiTest state


{-| Simulate a bracketed paste event. Delivers the text as a single `OnPaste`
event, just like a real terminal with bracketed paste mode enabled. Use this
instead of typing character-by-character when testing paste behavior.

    test
        |> TuiTest.pressKey 'c'              -- open commit dialog
        |> TuiTest.paste "fix: null pointer"  -- paste commit message
        |> TuiTest.ensureViewHas "fix: null pointer"

-}
paste : String -> TuiTest model msg -> TuiTest model msg
paste pastedText (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "paste called after TUI exited" }

        ( Nothing, Nothing ) ->
            let
                sub : Sub msg
                sub =
                    state.subscriptions state.model
            in
            case Sub.routeEvent sub (Sub.RawPaste pastedText) of
                Just msg ->
                    applyMsg ("paste \"" ++ truncateLabel pastedText ++ "\"") msg (TuiTest state)

                Nothing ->
                    TuiTest state


truncateLabel : String -> String
truncateLabel s =
    if String.length s > 30 then
        String.left 27 s ++ "..."

    else
        s


{-| Simulate a terminal resize. The framework handles resize automatically —
this updates the `Context` that `view` receives and routes the new size through
any `Tui.Sub.onContext` subscriptions.
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
                newContext : Context
                newContext =
                    { width = size.width, height = size.height, colorProfile = state.context.colorProfile }

                ( newModel, effect ) =
                    case Sub.routeEvent (state.subscriptions state.model) (Sub.RawContext { width = newContext.width, height = newContext.height }) of
                        Just msg ->
                            state.update msg state.model

                        Nothing ->
                            ( state.model, Effect.none )

                newPendingEffects : List (BackendTask FatalError msg)
                newPendingEffects =
                    state.pendingEffects ++ extractBackendTasks effect

                viewFn : Context -> Screen
                viewFn =
                    \ctx -> state.view ctx newModel

                snapshot : Snapshot
                snapshot =
                    { label = "resize " ++ String.fromInt size.width ++ "×" ++ String.fromInt size.height
                    , screen = state.view newContext newModel
                    , rerender = viewFn
                    , hasPendingEffects = not (List.isEmpty newPendingEffects)
                    , modelState = Maybe.map (\f -> f newModel) state.modelToString
                    }
            in
            TuiTest
                { state
                    | model = newModel
                    , context = newContext
                    , pendingEffects = newPendingEffects
                    , exited = checkForExit effect
                    , snapshots = state.snapshots ++ [ snapshot ]
                }


{-| Simulate a left mouse click at the given row and column (0-based).

    test |> TuiTest.click { row = 3, col = 5 }

-}
click : { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
click pos =
    simulateMouseEvent
        ("click (" ++ String.fromInt pos.row ++ "," ++ String.fromInt pos.col ++ ")")
        (Tui.Click { row = pos.row, col = pos.col, button = Tui.LeftButton })


{-| Find a line containing the given text and simulate a click on it.
Like elm-program-test's `clickButton` — finds elements by content instead of
coordinates, making tests resilient to layout changes.

    test |> TuiTest.clickText "def5678"

Fails with a helpful message if the text is not found on screen.

-}
clickText : String -> TuiTest model msg -> TuiTest model msg
clickText needle (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "clickText called after TUI exited" }

        ( Nothing, Nothing ) ->
            let
                screenLines : List String
                screenLines =
                    Tui.toLines (state.view state.context state.model)

                maybeRow : Maybe Int
                maybeRow =
                    screenLines
                        |> List.indexedMap Tuple.pair
                        |> List.filter (\( _, line ) -> String.contains needle line)
                        |> List.head
                        |> Maybe.map Tuple.first
            in
            case maybeRow of
                Just row ->
                    simulateMouseEvent
                        ("clickText \"" ++ needle ++ "\"")
                        (Tui.Click { row = row, col = 1, button = Tui.LeftButton })
                        (TuiTest state)

                Nothing ->
                    TuiTest
                        { state
                            | error =
                                Just
                                    ("clickText: could not find \""
                                        ++ needle
                                        ++ "\" on screen.\n\nThe screen contains:\n\n"
                                        ++ indentScreenText (Tui.toString (state.view state.context state.model))
                                    )
                        }


{-| Simulate a scroll-down event at the given position.
-}
scrollDown : { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
scrollDown pos =
    simulateMouseEvent
        ("scrollDown (" ++ String.fromInt pos.row ++ "," ++ String.fromInt pos.col ++ ")")
        (Tui.ScrollDown { row = pos.row, col = pos.col, amount = 1 })


{-| Simulate a scroll-up event at the given position.
-}
scrollUp : { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
scrollUp pos =
    simulateMouseEvent
        ("scrollUp (" ++ String.fromInt pos.row ++ "," ++ String.fromInt pos.col ++ ")")
        (Tui.ScrollUp { row = pos.row, col = pos.col, amount = 1 })


simulateMouseEvent : String -> Tui.MouseEvent -> TuiTest model msg -> TuiTest model msg
simulateMouseEvent label mouseEvent (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "mouse event after TUI exited" }

        ( Nothing, Nothing ) ->
            let
                sub : Sub msg
                sub =
                    state.subscriptions state.model
            in
            case Sub.routeEvent sub (Sub.RawMouse mouseEvent) of
                Just msg ->
                    applyMsg label msg (TuiTest state)

                Nothing ->
                    TuiTest state


{-| Send a message directly through `update`. Useful for simulating
`BackendTask` results without needing the full simulation infrastructure.

    test
        |> TuiTest.pressKey 's'
        |> TuiTest.sendMsg (StagingComplete "file.elm")
        |> TuiTest.ensureViewHas "staged"

-}
sendMsg : msg -> TuiTest model msg -> TuiTest model msg
sendMsg msg =
    applyMsg "sendMsg" msg



-- BACKENDTASK SIMULATION


{-| The type of the `Test.BackendTask` pipeline used with
[`resolveEffect`](#resolveEffect). This is `Test.BackendTask.Internal.BackendTaskTest`
— the same type that `Test.BackendTask` functions operate on.
-}
type alias BackendTaskSimulator msg =
    BackendTaskTest.BackendTaskTest msg


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
    (BackendTaskSimulator msg -> BackendTaskSimulator msg)
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
                screenText : String
                screenText =
                    Tui.toString (state.view state.context state.model)

                result : Expectation
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
                screenText : String
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
                screenText : String
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
Fails if there are unresolved pending `BackendTask` effects — use
[`resolveEffect`](#resolveEffect) or [`sendMsg`](#sendMsg) to resolve them
before calling this.
-}
expectRunning : TuiTest model msg -> Expectation
expectRunning (TuiTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case ( state.exited, state.pendingEffects ) of
                ( Nothing, [] ) ->
                    Expect.pass

                ( Nothing, pending ) ->
                    Expect.fail (pendingEffectsError (List.length pending))

                ( Just code, _ ) ->
                    Expect.fail ("Expected TUI to be running, but it exited with code " ++ String.fromInt code)


{-| Assert that the TUI exited with code 0.
Fails if there are unresolved pending `BackendTask` effects.
-}
expectExit : TuiTest model msg -> Expectation
expectExit (TuiTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case ( state.exited, state.pendingEffects ) of
                ( Just 0, [] ) ->
                    Expect.pass

                ( Just 0, pending ) ->
                    Expect.fail (pendingEffectsError (List.length pending))

                ( Just code, _ ) ->
                    Expect.fail ("Expected exit code 0, but got " ++ String.fromInt code)

                ( Nothing, pending ) ->
                    if List.isEmpty pending then
                        Expect.fail "Expected TUI to exit, but it is still running"

                    else
                        Expect.fail (pendingEffectsError (List.length pending))


{-| Assert that the TUI exited with a specific exit code.
Fails if there are unresolved pending `BackendTask` effects.
-}
expectExitWith : Int -> TuiTest model msg -> Expectation
expectExitWith expectedCode (TuiTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case ( state.exited, state.pendingEffects ) of
                ( Just code, [] ) ->
                    if code == expectedCode then
                        Expect.pass

                    else
                        Expect.fail ("Expected exit code " ++ String.fromInt expectedCode ++ ", but got " ++ String.fromInt code)

                ( Just _, pending ) ->
                    Expect.fail (pendingEffectsError (List.length pending))

                ( Nothing, pending ) ->
                    if List.isEmpty pending then
                        Expect.fail ("Expected TUI to exit with code " ++ String.fromInt expectedCode ++ ", but it is still running")

                    else
                        Expect.fail (pendingEffectsError (List.length pending))


pendingEffectsError : Int -> String
pendingEffectsError count =
    "There "
        ++ (if count == 1 then
                "is 1 pending BackendTask effect"

            else
                "are " ++ String.fromInt count ++ " pending BackendTask effects"
           )
        ++ " that must be resolved before ending the test.\n\n"
        ++ "Use TuiTest.resolveEffect to simulate the response, or TuiTest.sendMsg to skip the BackendTask and provide the resulting Msg directly."



-- HELPERS


applyMsg : String -> msg -> TuiTest model msg -> TuiTest model msg
applyMsg label msg (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest state

        ( Nothing, Nothing ) ->
            let
                ( newModel, effect ) =
                    state.update msg state.model

                newPendingEffects : List (BackendTask FatalError msg)
                newPendingEffects =
                    extractBackendTasks effect

                viewFn : Context -> Screen
                viewFn =
                    \ctx -> state.view ctx newModel

                snapshot : Snapshot
                snapshot =
                    { label = label
                    , screen = state.view state.context newModel
                    , rerender = viewFn
                    , hasPendingEffects = not (List.isEmpty newPendingEffects)
                    , modelState = Maybe.map (\f -> f newModel) state.modelToString
                    }
            in
            TuiTest
                { state
                    | model = newModel
                    , pendingEffects = newPendingEffects
                    , exited = checkForExit effect
                    , snapshots = state.snapshots ++ [ snapshot ]
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
                        testResult : Result String msg
                        testResult =
                            simulate bt
                                |> BackendTaskTest.toResult
                    in
                    case testResult of
                        Ok msg ->
                            let
                                ( newModel, newEffect ) =
                                    state.update msg state.model

                                newPendingEffects : List (BackendTask FatalError msg)
                                newPendingEffects =
                                    rest ++ extractBackendTasks newEffect

                                viewFn : Context -> Screen
                                viewFn =
                                    \ctx -> state.view ctx newModel

                                snapshot : Snapshot
                                snapshot =
                                    { label = "resolveEffect"
                                    , screen = state.view state.context newModel
                                    , rerender = viewFn
                                    , hasPendingEffects = not (List.isEmpty newPendingEffects)
                                    , modelState = Maybe.map (\f -> f newModel) state.modelToString
                                    }
                            in
                            TuiTest
                                { state
                                    | model = newModel
                                    , pendingEffects = newPendingEffects
                                    , exited = checkForExit newEffect
                                    , snapshots = state.snapshots ++ [ snapshot ]
                                }

                        Err errMsg ->
                            TuiTest { state | error = Just ("Effect resolution failed: " ++ errMsg) }


extractBackendTasks : Effect msg -> List (BackendTask FatalError msg)
extractBackendTasks effect =
    -- elm-review: known-unoptimized-recursion
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
    -- elm-review: known-unoptimized-recursion
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


{-| Enable model state inspection in snapshots. Pass `Debug.toString` (or any
`model -> String` function) and each snapshot will include the pretty-printed
model state.

Since published packages cannot use `Debug.toString` directly, this must be
called from your test code:

    counterTest
        |> TuiTest.withModelToString Debug.toString
        |> TuiTest.pressKey 'k'
        |> TuiTest.toSnapshots
        |> List.map .modelState
        -- [ Just "{ count = 0 }", Just "{ count = 1 }" ]

For nicer formatting, use `prettifyValue Debug.toString` from
`dillonkearns/elm-snapshot` if you have it as a dependency.

-}
withModelToString : (model -> String) -> TuiTest model msg -> TuiTest model msg
withModelToString modelToString (TuiTest state) =
    let
        updatedSnapshots : List Snapshot
        updatedSnapshots =
            state.snapshots
                |> List.map
                    (\snapshot ->
                        { snapshot
                            | modelState =
                                Just (modelToString state.model)
                        }
                    )
    in
    TuiTest
        { state
            | modelToString = Just modelToString
            , snapshots = updatedSnapshots
        }


{-| Extract the recorded snapshots from a test pipeline. Each step in the
pipeline (start, resize, pressKey, resolveEffect, sendMsg) records a snapshot
of the screen, the action label, and whether effects are pending.

If the pipeline encountered an error, a final snapshot with the error message
is appended so it's visible in the stepper.

Use this with the interactive test stepper to visualize a test run step by step.

-}
toSnapshots : TuiTest model msg -> List Snapshot
toSnapshots (TuiTest state) =
    case state.error of
        Just errorMsg ->
            let
                errorScreen : Screen
                errorScreen =
                    Tui.text errorMsg
            in
            state.snapshots
                ++ [ { label = "ERROR"
                     , screen = errorScreen
                     , rerender = \_ -> errorScreen
                     , hasPendingEffects = False
                     , modelState = Nothing
                     }
                   ]

        Nothing ->
            state.snapshots


keyEventLabel : KeyEvent -> String
keyEventLabel event =
    let
        keyName : String
        keyName =
            case event.key of
                Tui.Character c ->
                    "'" ++ String.fromChar c ++ "'"

                Tui.Enter ->
                    "Enter"

                Tui.Escape ->
                    "Escape"

                Tui.Tab ->
                    "Tab"

                Tui.Backspace ->
                    "Backspace"

                Tui.Delete ->
                    "Delete"

                Tui.Arrow dir ->
                    "Arrow "
                        ++ (case dir of
                                Tui.Up ->
                                    "Up"

                                Tui.Down ->
                                    "Down"

                                Tui.Left ->
                                    "Left"

                                Tui.Right ->
                                    "Right"
                           )

                Tui.FunctionKey n ->
                    "F" ++ String.fromInt n

                Tui.Home ->
                    "Home"

                Tui.End ->
                    "End"

                Tui.PageUp ->
                    "PageUp"

                Tui.PageDown ->
                    "PageDown"

        modPrefix : String
        modPrefix =
            event.modifiers
                |> List.map
                    (\m ->
                        case m of
                            Tui.Ctrl ->
                                "Ctrl+"

                            Tui.Alt ->
                                "Alt+"

                            Tui.Shift ->
                                "Shift+"
                    )
                |> String.concat
    in
    "pressKey " ++ modPrefix ++ keyName
