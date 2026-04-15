module Tui.Test exposing
    ( TuiTest, Test, Outcome
    , start, startWithContext, startApp, startAppWithContext
    , pressKey, pressKeyWith, pressKeyN, paste, resize
    , click, clickText, scrollDown, scrollUp, scrollDownN, scrollUpN
    , sendMsg, advanceTime
    , BackendTaskSimulator, resolveEffect
    , ensureView, ensureViewHas, ensureViewDoesNotHave
    , ensureModel, annotateAssertion
    , StyleCheck, bold, dim, italic, underline, fg, bg
    , ensureViewHasStyled, ensureViewDoesNotHaveStyled
    , expectRunning, expectExit, expectExitWith
    , test, describe, toTest, done, toNamedSnapshots
    , Snapshot, toSnapshots, withModelToString
    )

{-| Test TUI scripts without a real terminal — simulate events, resolve
effects, and assert on screen output. Uses a pipeline API inspired by
[`elm-program-test`](https://package.elm-lang.org/packages/avh4/elm-program-test/latest/).

Build named tests by turning a `TuiTest` scenario into an `Outcome`, then
wrapping those outcomes in a `Test` tree. That same `Test` value can be:

  - run headlessly through [`toTest`](#toTest) with `elm-test`

  - visualized through `elm-pages test`, which reads the same named tests and
    shows their recorded snapshots in the terminal stepper

    import Tui
    import Test
    import Tui.Effect as Effect
    import Tui.Sub
    import Tui.Test as TuiTest

    type Msg
    = Increment
    | Quit

    tuiTests : TuiTest.Test
    tuiTests =
    TuiTest.describe "Counter"
    [ TuiTest.test "increments with j" <|
    TuiTest.start
    { data = ()
    , init = () -> ( 0, Effect.none )
    , update =
    \\msg count ->
    case msg of
    Increment ->
    ( count + 1, Effect.none )

                                Quit ->
                                    ( count, Effect.exit )
                    , view = \_ count -> Tui.text ("Count: " ++ String.fromInt count)
                    , subscriptions = \_ -> Tui.Sub.onKeyPress keyToMsg
                    }
                    |> TuiTest.pressKey 'j'
                    |> TuiTest.ensureViewHas "Count: 1"
                    |> TuiTest.expectRunning
            ]

```
keyToMsg : Tui.KeyEvent -> Msg
keyToMsg event =
    case event.key of
        Tui.Character 'j' ->
            Increment

        _ ->
            Quit

suite : Test.Test
suite =
    TuiTest.toTest tuiTests
```

@docs TuiTest, Test, Outcome


## Starting a Test

Pass the same config you'd give to [`Tui.Program.program`](Tui-Program#program),
but with `data` already resolved (not a `BackendTask`). If your app uses
`Tui.Sub.onContext`, the initial context is fired automatically.

@docs start, startWithContext, startApp, startAppWithContext


## Simulating Events

Simulate user interactions in the order they would happen. Each function
threads the `TuiTest` through the app's `update` and captures the new screen.

@docs pressKey, pressKeyWith, pressKeyN, paste, resize

@docs click, clickText, scrollDown, scrollUp, scrollDownN, scrollUpN

@docs sendMsg, advanceTime


## Resolving Effects

When your `update` returns a `Tui.Effect` that performs a
`BackendTask` (via `Effect.perform`),
the test captures it as a pending effect. Use `resolveEffect` to simulate
the `BackendTask` result:

    |> TuiTest.resolveEffect
        (BackendTaskTest.simulateCommand "git" "M src/Main.elm")

@docs BackendTaskSimulator, resolveEffect


## Screen Assertions

Assert on the plain text content of the current screen. Failed assertions
show the full screen output for easy debugging.

@docs ensureView, ensureViewHas, ensureViewDoesNotHave

@docs ensureModel, annotateAssertion


## Styled Text Assertions

Assert on text that appears with specific styling (bold, color, etc.).
Adjacent spans with the same style are merged before matching, so
fragmented rendering like `<red>ERROR</red><red> message</red>` is
treated as a single `"ERROR message"` red region.

@docs StyleCheck, bold, dim, italic, underline, fg, bg
@docs ensureViewHasStyled, ensureViewDoesNotHaveStyled


## Final Assertions

End a `TuiTest` scenario with one of these to produce an `Outcome`. If
pending effects remain unresolved, `expectRunning` and `expectExit`
will fail — ensuring you don't accidentally ignore effects. Use
[`test`](#test) and [`describe`](#describe) to turn those outcomes into a named
test tree, then [`toTest`](#toTest) to run it with `elm-test`.

@docs expectRunning, expectExit, expectExitWith

@docs test, describe, toTest, done, toNamedSnapshots


## Snapshots

Record screen snapshots at each step for the interactive test stepper
([`elm-pages test`](https://elm-pages.com)). Navigate snapshots with
arrow keys to visually step through your test.

@docs Snapshot, toSnapshots, withModelToString

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Test as ElmTest
import Test.BackendTask.Internal as BackendTaskTest
import Test.Runner
import Time
import Tui exposing (Context, KeyEvent, Screen)
import Tui.Effect as Effect exposing (Effect)
import Tui.Effect.Internal as EffectInternal
import Tui.Program
import Tui.Screen.Internal as ScreenInternal
import Tui.Sub exposing (Sub)
import Tui.Sub.Internal as SubInternal


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
    , currentTime : Int
    , tickFireTimes : Dict Int Int
    }


{-| A snapshot of the TUI state at a point in the test pipeline. Used by
[`toSnapshots`](#toSnapshots) for the interactive test stepper.

`screen` is the `Tui.Screen` value (preserving styling), not a plain string.
Use `Tui.toString` to get plain text, or render it through the TUI pipeline
for styled output.

-}
type alias Snapshot =
    { label : String
    , screen : Screen
    , hasPendingEffects : Bool
    , modelState : Maybe String
    , assertions : List String
    }


{-| A named tree of TUI tests.

Use [`test`](#test) for leaf tests and [`describe`](#describe) to group them,
then pass the resulting value to [`toTest`](#toTest) for `elm-test` or expose it
for `elm-pages test`.

    import Test
    import Tui.Test as TuiTest

    tuiTests : TuiTest.Test
    tuiTests =
        TuiTest.describe "Counter"
            [ TuiTest.test "increments" <|
                counterScenario
                    |> TuiTest.pressKey 'j'
                    |> TuiTest.expectRunning
            ]

    suite : Test.Test
    suite =
        TuiTest.toTest tuiTests

-}
type Test
    = SingleTest String Outcome
    | Describe String (List Test)


{-| The finalized result of a single `TuiTest` scenario.

Create an `Outcome` with [`expectRunning`](#expectRunning),
[`expectExit`](#expectExit), or [`expectExitWith`](#expectExitWith). You can
wrap it in a named test with [`test`](#test) or run it directly with
[`done`](#done).

    import Expect
    import Tui.Test as TuiTest

    result : TuiTest.Outcome
    result =
        counterScenario
            |> TuiTest.pressKey 'q'
            |> TuiTest.expectExit

    check : Expect.Expectation
    check =
        TuiTest.done result

-}
type Outcome
    = Outcome
        { expectation : Expectation
        , snapshots : List Snapshot
        }


{-| Start a TUI test with a default 80×24 terminal and `TrueColor` profile.
Provide the same config record you pass to `Tui.Program.program`, but with `data`
already resolved (not a `BackendTask`).

If your app subscribes to `Tui.Sub.onContext`, the initial context is fired
automatically (matching runtime behavior).

    TuiTest.start
        { data = { files = [ "Main.elm" ] }
        , init = MyTui.init
        , update = MyTui.update
        , view = MyTui.view
        , subscriptions = MyTui.subscriptions
        }

Use [`startWithContext`](#startWithContext) for a custom terminal size.

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


{-| Like `start` but with a custom terminal context (dimensions and color
profile). Useful for testing responsive layouts or color profile adaptation.

    TuiTest.startWithContext
        { width = 120, height = 40, colorProfile = Tui.TrueColor }
        { data = (), ... }

If your app subscribes to `Tui.Sub.onContext`, the initial context is fired
automatically (matching runtime behavior).

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
            SubInternal.routeEvents
                (config.subscriptions initialModel)
                (SubInternal.RawContext { width = context.width, height = context.height })
                |> List.foldl
                    (\msg ( m, accEffect ) ->
                        let
                            ( newModel, newEffect ) =
                                config.update msg m
                        in
                        ( newModel, Effect.batch [ accEffect, newEffect ] )
                    )
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
              , hasPendingEffects = not (List.isEmpty pendingEffects)
              , modelState = Nothing
              , assertions = []
              }
            ]
        , modelToString = Nothing
        , currentTime = 0
        , tickFireTimes = Dict.empty
        }


{-| Start a test from a [`Tui.Program.App`](Tui-Program#App), supplying an
already-resolved `data` value rather than letting the real BackendTask run.
Use this with `Tui.Layout.compileApp` output:

    TuiTest.startApp ()
        (Layout.compileApp
            { data = BackendTask.succeed ()
            , init = init
            , update = update
            , view = view
            , bindings = bindings
            , status = status
            , modal = modal
            , onRawEvent = Nothing
            }
        )

The `app.data` BackendTask is ignored — tests supply resolved data directly
so they stay pure.

-}
startApp :
    data
    -> Tui.Program.App data model msg
    -> TuiTest model msg
startApp data app =
    start
        { data = data
        , init = app.init
        , update = app.update
        , view = app.view
        , subscriptions = app.subscriptions
        }


{-| Like [`startApp`](#startApp) but with a custom terminal context.

    TuiTest.startAppWithContext
        { width = 120, height = 40, colorProfile = Tui.TrueColor }
        ()
        compiledApp

-}
startAppWithContext :
    Context
    -> data
    -> Tui.Program.App data model msg
    -> TuiTest model msg
startAppWithContext context data app =
    startWithContext context
        { data = data
        , init = app.init
        , update = app.update
        , view = app.view
        , subscriptions = app.subscriptions
        }



-- SIMULATING EVENTS


{-| Simulate pressing a character key with no modifiers.

    test |> TuiTest.pressKey 'j'

-}
pressKey : Char -> TuiTest model msg -> TuiTest model msg
pressKey char =
    pressKeyWith { key = Tui.Character char, modifiers = [] }


{-| Simulate pressing a character key N times.

    -- Navigate down 7 items
    test |> TuiTest.pressKeyN 7 'j'

-}
pressKeyN : Int -> Char -> TuiTest model msg -> TuiTest model msg
pressKeyN n char tuiTest =
    List.foldl (\_ acc -> pressKey char acc) tuiTest (List.range 1 n)


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
            SubInternal.routeEvents sub (SubInternal.RawKeyPress keyEvent)
                |> List.foldl (applyMsg (keyEventLabel keyEvent)) (TuiTest state)


{-| Simulate a bracketed paste event. Delivers the text as a single `OnPaste`
event, just like a real terminal with bracketed paste mode enabled. Use this
instead of typing character-by-character when testing paste behavior.

    test
        |> TuiTest.pressKey 'c'
        -- open commit dialog
        |> TuiTest.paste "fix: null pointer"
        -- paste commit message
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
            SubInternal.routeEvents sub (SubInternal.RawPaste pastedText)
                |> List.foldl
                    (applyMsg ("paste \"" ++ truncateLabel pastedText ++ "\""))
                    (TuiTest state)


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
                    SubInternal.routeEvents
                        (state.subscriptions state.model)
                        (SubInternal.RawContext { width = newContext.width, height = newContext.height })
                        |> List.foldl
                            (\msg ( m, accEffect ) ->
                                let
                                    ( m2, newEffect ) =
                                        state.update msg m
                                in
                                ( m2, Effect.batch [ accEffect, newEffect ] )
                            )
                            ( state.model, Effect.none )

                newPendingEffects : List (BackendTask FatalError msg)
                newPendingEffects =
                    state.pendingEffects ++ extractBackendTasks effect

                snapshot : Snapshot
                snapshot =
                    { label = "resize " ++ String.fromInt size.width ++ "×" ++ String.fromInt size.height
                    , screen = state.view newContext newModel
                    , hasPendingEffects = not (List.isEmpty newPendingEffects)
                    , modelState = Maybe.map (\f -> f newModel) state.modelToString
                    , assertions = []
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
                    Tui.toString (state.view state.context state.model)
                        |> String.split "\n"

                maybeMatch : Maybe { row : Int, col : Int }
                maybeMatch =
                    screenLines
                        |> List.indexedMap Tuple.pair
                        |> List.filterMap
                            (\( idx, line ) ->
                                case String.indexes needle line of
                                    first :: _ ->
                                        Just { row = idx, col = first }

                                    [] ->
                                        Nothing
                            )
                        |> List.head
            in
            case maybeMatch of
                Just match ->
                    simulateMouseEvent
                        ("clickText \"" ++ needle ++ "\"")
                        (Tui.Click { row = match.row, col = match.col, button = Tui.LeftButton })
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


{-| Simulate N scroll-down events at the given position.

    test |> TuiTest.scrollDownN 10 { row = 3, col = 60 }

-}
scrollDownN : Int -> { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
scrollDownN n pos tuiTest =
    List.foldl (\_ acc -> scrollDown pos acc) tuiTest (List.range 1 n)


{-| Simulate N scroll-up events at the given position.

    test |> TuiTest.scrollUpN 5 { row = 3, col = 60 }

-}
scrollUpN : Int -> { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
scrollUpN n pos tuiTest =
    List.foldl (\_ acc -> scrollUp pos acc) tuiTest (List.range 1 n)


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
            SubInternal.routeEvents sub (SubInternal.RawMouse mouseEvent)
                |> List.foldl (applyMsg label) (TuiTest state)


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


{-| Advance simulated time by the given number of milliseconds. Any
[`Tui.Sub.everyMillis`](Tui-Sub#everyMillis) subscriptions fire for each
interval boundary crossed, passing the simulated `Time.Posix` at the moment
of fire to the user's message constructor.

    import Time

    TuiTest.test "animation advances one frame per 50ms tick" <|
        spinnerTest
            |> TuiTest.advanceTime 50
            |> TuiTest.ensureViewHas "frame 1"
            |> TuiTest.advanceTime 50
            |> TuiTest.ensureViewHas "frame 2"
            |> TuiTest.expectRunning

Multi-interval subscriptions fire independently at their own rates. If
multiple ticks fall in the same `advanceTime` call, they are delivered to
`update` in chronological order; same-timestamp ticks from different
intervals fire in subscription order. Catch-up semantics match the runtime:
each interval fires at most once per `advanceTime` call with the actual
simulated fire time, not the target time.

The starting simulated clock is `1970-01-01T00:00:00Z` (posix 0). The first
fire of `everyMillis n _` is at simulated posix `n`.

-}
advanceTime : Int -> TuiTest model msg -> TuiTest model msg
advanceTime deltaMs (TuiTest state) =
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest state

        ( _, Just _ ) ->
            TuiTest { state | error = Just "advanceTime called after TUI exited" }

        ( Nothing, Nothing ) ->
            advanceTimeHelp (state.currentTime + deltaMs) (TuiTest state)


advanceTimeHelp : Int -> TuiTest model msg -> TuiTest model msg
advanceTimeHelp targetTime (TuiTest state) =
    -- elm-review: known-unoptimized-recursion
    case ( state.error, state.exited ) of
        ( Just _, _ ) ->
            TuiTest { state | currentTime = targetTime }

        ( _, Just _ ) ->
            TuiTest { state | currentTime = targetTime }

        ( Nothing, Nothing ) ->
            let
                sub : Sub msg
                sub =
                    state.subscriptions state.model

                intervals : List Int
                intervals =
                    SubInternal.getTickIntervals sub

                nextFires : List ( Int, Int )
                nextFires =
                    intervals
                        |> List.map
                            (\interval ->
                                let
                                    lastFire : Int
                                    lastFire =
                                        Dict.get interval state.tickFireTimes
                                            |> Maybe.withDefault 0
                                in
                                ( interval, lastFire + interval )
                            )
                        |> List.filter (\( _, t ) -> t <= targetTime)
                        |> List.sortBy Tuple.second
            in
            case nextFires of
                [] ->
                    TuiTest { state | currentTime = targetTime }

                ( interval, fireTime ) :: _ ->
                    let
                        rawEvent : SubInternal.RawEvent
                        rawEvent =
                            SubInternal.RawTick
                                { interval = interval
                                , time = Time.millisToPosix fireTime
                                }

                        stateWithClock : State model msg
                        stateWithClock =
                            { state
                                | currentTime = fireTime
                                , tickFireTimes =
                                    Dict.insert interval fireTime state.tickFireTimes
                            }

                        msgs : List msg
                        msgs =
                            SubInternal.routeEvents sub rawEvent

                        label : String
                        label =
                            "advance " ++ String.fromInt fireTime ++ "ms"
                    in
                    List.foldl (applyMsg label) (TuiTest stateWithClock) msgs
                        |> advanceTimeHelp targetTime



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

    TuiTest.test "fetches stars on Enter" <|
        starsTest
            |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
            |> TuiTest.resolveEffect
                (BackendTaskTest.simulateHttpGet
                    "https://api.github.com/repos/elm/core"
                    (Encode.object [ ( "stargazers_count", Encode.int 7500 ) ])
                )
            |> TuiTest.ensureViewHas "Stars: 7500"
            |> TuiTest.expectRunning

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
                    TuiTest (recordAssertion "ensureView ✓" state)


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
                TuiTest (recordAssertion ("ensureViewHas \"" ++ needle ++ "\" ✓") state)

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
                TuiTest (recordAssertion ("ensureViewDoesNotHave \"" ++ needle ++ "\" ✓") state)


{-| Assert on the model directly. Useful for verifying internal state that
isn't visible in the rendered output, or for building higher-level test
helpers that query opaque framework state (like `Layout.FrameworkModel`).

    TuiTest.test "counter is at 5" <|
        counterApp
            |> TuiTest.pressKeyN 5 'j'
            |> TuiTest.ensureModel
                (\model -> Expect.equal 5 model.count)
            |> TuiTest.expectRunning

-}
ensureModel : (model -> Expectation) -> TuiTest model msg -> TuiTest model msg
ensureModel assertion (TuiTest state) =
    case state.error of
        Just _ ->
            TuiTest state

        Nothing ->
            case getFailureMessage (assertion state.model) of
                Just msg ->
                    TuiTest { state | error = Just ("ensureModel failed:\n" ++ msg) }

                Nothing ->
                    TuiTest state


{-| Add an assertion label to the most recent snapshot. The stepper displays
these in green beneath the action label so you can see which checks happened
at each step.

Use this when building custom assertion helpers on top of `ensureModel`:

    ensureFocusedPane paneId =
        TuiTest.ensureModel (\m -> ...)
            >> TuiTest.annotateAssertion ("ensureFocusedPane \"" ++ paneId ++ "\" ✓")

-}
annotateAssertion : String -> TuiTest model msg -> TuiTest model msg
annotateAssertion description (TuiTest state) =
    case state.error of
        Just _ ->
            TuiTest state

        Nothing ->
            TuiTest (recordAssertion description state)



-- STYLED TEXT ASSERTIONS


{-| A check on a single style attribute. Combine multiple checks in a list
to require all of them — `[ bold, fg Ansi.Color.red ]` means "bold AND red."
-}
type StyleCheck
    = StyleCheck (ScreenInternal.FlatStyle -> Bool)


{-| Match bold text.

    |> TuiTest.ensureViewHasStyled [ TuiTest.bold ] "selected item"

-}
bold : StyleCheck
bold =
    StyleCheck .bold


{-| Match dim text.
-}
dim : StyleCheck
dim =
    StyleCheck .dim


{-| Match italic text.
-}
italic : StyleCheck
italic =
    StyleCheck .italic


{-| Match underlined text.
-}
underline : StyleCheck
underline =
    StyleCheck .underline


{-| Match text with a specific foreground color.

    |> TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "Error"

-}
fg : Ansi.Color.Color -> StyleCheck
fg color =
    StyleCheck (\s -> s.foreground == Just color)


{-| Match text with a specific background color.

    |> TuiTest.ensureViewHasStyled [ TuiTest.bg Ansi.Color.blue ] "Selected"

-}
bg : Ansi.Color.Color -> StyleCheck
bg color =
    StyleCheck (\s -> s.background == Just color)


{-| Assert that the screen contains the given text rendered with ALL of the
specified style checks. Adjacent spans that satisfy the checks are merged
before matching, so fragmented rendering is handled correctly.

    TuiTest.test "selected item is highlighted" <|
        myTest
            |> TuiTest.ensureViewHasStyled [ TuiTest.bold, TuiTest.fg Ansi.Color.yellow ] "selected"
            |> TuiTest.expectRunning

-}
ensureViewHasStyled : List StyleCheck -> String -> TuiTest model msg -> TuiTest model msg
ensureViewHasStyled checks needle (TuiTest state) =
    case state.error of
        Just _ ->
            TuiTest state

        Nothing ->
            let
                screen : Screen
                screen =
                    state.view state.context state.model
            in
            if containsStyledText checks needle screen then
                TuiTest (recordAssertion ("ensureViewHasStyled " ++ describeChecks checks ++ " \"" ++ needle ++ "\" ✓") state)

            else
                let
                    screenText : String
                    screenText =
                        Tui.toString screen
                in
                TuiTest
                    { state
                        | error =
                            Just
                                ("ensureViewHasStyled: expected screen to contain:\n\n    \""
                                    ++ needle
                                    ++ "\"\n\nwith style "
                                    ++ describeChecks checks
                                    ++ "\n\nbut the screen was:\n\n"
                                    ++ indentScreenText screenText
                                )
                    }


{-| Assert that the screen does NOT contain the given text with ALL of the
specified style checks.

    TuiTest.test "error text is not bold" <|
        myTest
            |> TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold ] "Error"
            |> TuiTest.expectRunning

-}
ensureViewDoesNotHaveStyled : List StyleCheck -> String -> TuiTest model msg -> TuiTest model msg
ensureViewDoesNotHaveStyled checks needle (TuiTest state) =
    case state.error of
        Just _ ->
            TuiTest state

        Nothing ->
            let
                screen : Screen
                screen =
                    state.view state.context state.model
            in
            if containsStyledText checks needle screen then
                let
                    screenText : String
                    screenText =
                        Tui.toString screen
                in
                TuiTest
                    { state
                        | error =
                            Just
                                ("ensureViewDoesNotHaveStyled: expected screen NOT to contain:\n\n    \""
                                    ++ needle
                                    ++ "\"\n\nwith style "
                                    ++ describeChecks checks
                                    ++ "\n\nbut the screen was:\n\n"
                                    ++ indentScreenText screenText
                                )
                    }

            else
                TuiTest (recordAssertion ("ensureViewDoesNotHaveStyled " ++ describeChecks checks ++ " \"" ++ needle ++ "\" ✓") state)


{-| Check if any line contains the needle as a substring within a contiguous
region where all spans satisfy the style checks. Adjacent matching spans are
merged before searching.
-}
containsStyledText : List StyleCheck -> String -> Screen -> Bool
containsStyledText checks needle screen =
    let
        predicate : ScreenInternal.FlatStyle -> Bool
        predicate style =
            List.all (\(StyleCheck check) -> check style) checks

        spanLines : List (List ScreenInternal.Span)
        spanLines =
            ScreenInternal.flattenToSpanLines tuiStyleToFlatStyle screen
    in
    List.any (containsStyledInLine predicate needle) spanLines


containsStyledInLine : (ScreenInternal.FlatStyle -> Bool) -> String -> List ScreenInternal.Span -> Bool
containsStyledInLine predicate needle spans =
    containsStyledInLineHelp predicate needle "" spans


containsStyledInLineHelp : (ScreenInternal.FlatStyle -> Bool) -> String -> String -> List ScreenInternal.Span -> Bool
containsStyledInLineHelp predicate needle acc spans =
    case spans of
        [] ->
            String.contains needle acc

        span :: rest ->
            if predicate span.style then
                containsStyledInLineHelp predicate needle (acc ++ span.text) rest

            else if String.contains needle acc then
                True

            else
                containsStyledInLineHelp predicate needle "" rest


describeChecks : List StyleCheck -> String
describeChecks checks =
    let
        names : List String
        names =
            List.filterMap describeCheck checks
    in
    case names of
        [] ->
            "(any style)"

        _ ->
            "[" ++ String.join ", " names ++ "]"


describeCheck : StyleCheck -> Maybe String
describeCheck (StyleCheck check) =
    -- Check which attribute this check tests by probing with a styled FlatStyle
    let
        base : ScreenInternal.FlatStyle
        base =
            ScreenInternal.defaultFlatStyle
    in
    if check { base | bold = True } && not (check base) then
        Just "bold"

    else if check { base | dim = True } && not (check base) then
        Just "dim"

    else if check { base | italic = True } && not (check base) then
        Just "italic"

    else if check { base | underline = True } && not (check base) then
        Just "underline"

    else if check { base | foreground = Just Ansi.Color.white } && not (check base) then
        Just "fg color"

    else if check { base | background = Just Ansi.Color.white } && not (check base) then
        Just "bg color"

    else
        Nothing


tuiStyleToFlatStyle : Tui.Style -> ScreenInternal.FlatStyle
tuiStyleToFlatStyle s =
    let
        def : ScreenInternal.FlatStyle
        def =
            ScreenInternal.defaultFlatStyle

        base : ScreenInternal.FlatStyle
        base =
            { def
                | foreground = s.fg
                , background = s.bg
                , hyperlink = s.hyperlink
            }
    in
    List.foldl applyAttr base s.attributes


applyAttr : Tui.Attribute -> ScreenInternal.FlatStyle -> ScreenInternal.FlatStyle
applyAttr attr flatStyle =
    case attr of
        Tui.Bold ->
            { flatStyle | bold = True }

        Tui.Dim ->
            { flatStyle | dim = True }

        Tui.Italic ->
            { flatStyle | italic = True }

        Tui.Underline ->
            { flatStyle | underline = True }

        Tui.Strikethrough ->
            { flatStyle | strikethrough = True }

        Tui.Inverse ->
            { flatStyle | inverse = True }



-- TERMINAL ASSERTIONS


{-| Assert that the TUI is still running (has not exited).
Fails if there are unresolved pending `BackendTask` effects — use
[`resolveEffect`](#resolveEffect) or [`sendMsg`](#sendMsg) to resolve them
before calling this. Returns an [`Outcome`](#Outcome) so the same scenario can
be wrapped in a named [`test`](#test) or inspected directly with [`done`](#done).
-}
expectRunning : TuiTest model msg -> Outcome
expectRunning (TuiTest state) =
    outcomeFromState state <|
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
Fails if there are unresolved pending `BackendTask` effects. Returns an
[`Outcome`](#Outcome) so the same scenario can be wrapped in a named
[`test`](#test) or inspected directly with [`done`](#done).
-}
expectExit : TuiTest model msg -> Outcome
expectExit (TuiTest state) =
    outcomeFromState state <|
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
Fails if there are unresolved pending `BackendTask` effects. Returns an
[`Outcome`](#Outcome) so the same scenario can be wrapped in a named
[`test`](#test) or inspected directly with [`done`](#done).
-}
expectExitWith : Int -> TuiTest model msg -> Outcome
expectExitWith expectedCode (TuiTest state) =
    outcomeFromState state <|
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


{-| Wrap a single named TUI test.

    import Tui.Test as TuiTest

    counterTests : TuiTest.Test
    counterTests =
        TuiTest.test "increments" <|
            counterScenario
                |> TuiTest.pressKey 'j'
                |> TuiTest.expectRunning

-}
test : String -> Outcome -> Test
test label outcome =
    SingleTest label outcome


{-| Group TUI tests under a shared heading.

    import Tui.Test as TuiTest

    counterTests : TuiTest.Test
    counterTests =
        TuiTest.describe "Counter"
            [ TuiTest.test "increments" <|
                counterScenario
                    |> TuiTest.pressKey 'j'
                    |> TuiTest.expectRunning
            , TuiTest.test "quits" <|
                counterScenario
                    |> TuiTest.pressKey 'q'
                    |> TuiTest.expectExit
            ]

-}
describe : String -> List Test -> Test
describe label children =
    Describe label children


{-| Convert a named TUI test tree into an `elm-test` `Test.Test`.

    import Test
    import Tui.Test as TuiTest

    suite : Test.Test
    suite =
        TuiTest.toTest tuiTests

-}
toTest : Test -> ElmTest.Test
toTest tuiTest =
    -- elm-review: known-unoptimized-recursion
    case tuiTest of
        SingleTest label outcome ->
            ElmTest.test label <|
                \() ->
                    done outcome

        Describe label children ->
            ElmTest.describe label (List.map toTest children)


{-| Run a single finalized outcome directly as an `Expect.Expectation`.

This is mostly useful in low-level helper tests for `Tui.Test` itself. Most
user code will prefer wrapping outcomes in [`test`](#test) and [`describe`](#describe),
then calling [`toTest`](#toTest).

    import Expect
    import Tui.Test as TuiTest

    expectation : Expect.Expectation
    expectation =
        counterScenario
            |> TuiTest.pressKey 'q'
            |> TuiTest.expectExit
            |> TuiTest.done

-}
done : Outcome -> Expectation
done (Outcome outcome) =
    outcome.expectation


{-| Flatten a named TUI test tree into named snapshot sequences.

`elm-pages test` uses this to populate the interactive terminal stepper. The
names include any enclosing [`describe`](#describe) labels so the selected test
is easy to identify.

    import Tui.Test as TuiTest

    snapshotNames : List String
    snapshotNames =
        tuiTests
            |> TuiTest.toNamedSnapshots
            |> List.map Tuple.first

-}
toNamedSnapshots : Test -> List ( String, List Snapshot )
toNamedSnapshots tuiTest =
    toNamedSnapshotsHelp [] tuiTest


toNamedSnapshotsHelp : List String -> Test -> List ( String, List Snapshot )
toNamedSnapshotsHelp ancestors tuiTest =
    -- elm-review: known-unoptimized-recursion
    case tuiTest of
        SingleTest label (Outcome outcome) ->
            [ ( String.join " / " (ancestors ++ [ label ])
              , outcome.snapshots
              )
            ]

        Describe label children ->
            children
                |> List.concatMap (toNamedSnapshotsHelp (ancestors ++ [ label ]))


outcomeFromState : State model msg -> Expectation -> Outcome
outcomeFromState state expectation =
    Outcome
        { expectation = expectation
        , snapshots = toSnapshots (TuiTest state)
        }


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

                snapshot : Snapshot
                snapshot =
                    { label = label
                    , screen = state.view state.context newModel
                    , hasPendingEffects = not (List.isEmpty newPendingEffects)
                    , modelState = Maybe.map (\f -> f newModel) state.modelToString
                    , assertions = []
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

                                snapshot : Snapshot
                                snapshot =
                                    { label = "resolveEffect"
                                    , screen = state.view state.context newModel
                                    , hasPendingEffects = not (List.isEmpty newPendingEffects)
                                    , modelState = Maybe.map (\f -> f newModel) state.modelToString
                                    , assertions = []
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
    extractBackendTasksHelp [ effect ] []


extractBackendTasksHelp : List (Effect msg) -> List (BackendTask FatalError msg) -> List (BackendTask FatalError msg)
extractBackendTasksHelp remaining collected =
    case remaining of
        [] ->
            List.reverse collected

        next :: rest ->
            case next of
                EffectInternal.None ->
                    extractBackendTasksHelp rest collected

                EffectInternal.Batch effects ->
                    extractBackendTasksHelp (List.reverse effects ++ rest) collected

                EffectInternal.RunBackendTask backendTask ->
                    extractBackendTasksHelp rest (backendTask :: collected)

                EffectInternal.Exit ->
                    extractBackendTasksHelp rest collected

                EffectInternal.ExitWithCode _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.Toast _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.ErrorToast _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.ResetScroll _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.ScrollTo _ _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.ScrollDown _ _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.ScrollUp _ _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.SetSelectedIndex _ _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.SelectFirst _ ->
                    extractBackendTasksHelp rest collected

                EffectInternal.FocusPane _ ->
                    extractBackendTasksHelp rest collected


checkForExit : Effect msg -> Maybe Int
checkForExit effect =
    checkForExitHelp [ effect ]


checkForExitHelp : List (Effect msg) -> Maybe Int
checkForExitHelp remaining =
    case remaining of
        [] ->
            Nothing

        next :: rest ->
            case next of
                EffectInternal.None ->
                    checkForExitHelp rest

                EffectInternal.Batch effects ->
                    checkForExitHelp (List.reverse effects ++ rest)

                EffectInternal.RunBackendTask _ ->
                    checkForExitHelp rest

                EffectInternal.Exit ->
                    Just 0

                EffectInternal.ExitWithCode code ->
                    Just code

                EffectInternal.Toast _ ->
                    checkForExitHelp rest

                EffectInternal.ErrorToast _ ->
                    checkForExitHelp rest

                EffectInternal.ResetScroll _ ->
                    checkForExitHelp rest

                EffectInternal.ScrollTo _ _ ->
                    checkForExitHelp rest

                EffectInternal.ScrollDown _ _ ->
                    checkForExitHelp rest

                EffectInternal.ScrollUp _ _ ->
                    checkForExitHelp rest

                EffectInternal.SetSelectedIndex _ _ ->
                    checkForExitHelp rest

                EffectInternal.SelectFirst _ ->
                    checkForExitHelp rest

                EffectInternal.FocusPane _ ->
                    checkForExitHelp rest


indentScreenText : String -> String
indentScreenText screenText =
    screenText
        |> String.lines
        |> List.map (\line -> "    " ++ line)
        |> String.join "\n"


{-| Append an assertion description to the most recent snapshot.
This doesn't create a new snapshot — the screen hasn't changed —
it just annotates the last action with what was checked.
-}
recordAssertion : String -> State model msg -> State model msg
recordAssertion description state =
    case List.reverse state.snapshots of
        last :: rest ->
            { state
                | snapshots =
                    List.reverse ({ last | assertions = last.assertions ++ [ description ] } :: rest)
            }

        [] ->
            state


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
                     , hasPendingEffects = False
                     , modelState = Nothing
                     , assertions = []
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
