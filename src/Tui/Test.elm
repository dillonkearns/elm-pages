module Tui.Test exposing
    ( TuiTest, Test, Outcome
    , start, startWithContext
    , pressKey, pressKeyWith, pressKeyN, paste, resize
    , click, clickText, scrollDown, scrollUp, scrollDownN, scrollUpN
    , sendMsg, advanceTime
    , resolveEffect, resolveEffectWith, BackendTaskSimulator
    , ensureView, ensureViewHas, ensureViewDoesNotHave
    , ensureModel, annotateAssertion
    , StyleCheck, bold, dim, italic, underline, fg, bg
    , ensureViewHasStyled, ensureViewDoesNotHaveStyled
    , expectRunning, expectExit, expectExitWith
    , test, describe, toTest, done, toNamedSnapshots
    , Snapshot, toSnapshots, withModelToString
    )

{-| Test a `Tui.program` the same way a user uses it: start the app, simulate
terminal events, and assert on the screen or model. Inspired by
[`elm-program-test`](https://package.elm-lang.org/packages/avh4/elm-program-test/latest/).

Typical flow:

  - Start with [`start`](#start) or [`startWithContext`](#startWithContext).
  - Simulate input with [`pressKey`](#pressKey), [`clickText`](#clickText),
    [`paste`](#paste), [`resize`](#resize), or [`advanceTime`](#advanceTime).
  - Resolve pending `BackendTask` effects with [`resolveEffect`](#resolveEffect)
    for the common case, or [`resolveEffectWith`](#resolveEffectWith) when you
    need custom HTTP/command simulation.
  - Finish with [`expectRunning`](#expectRunning), [`expectExit`](#expectExit),
    or [`expectExitWith`](#expectExitWith).

The same named tests can be:

  - Run headlessly through [`toTest`](#toTest) with `elm-test`
  - Visualized through `elm-pages test`, which reads
    [`toNamedSnapshots`](#toNamedSnapshots) and shows the recorded snapshots in
    the terminal stepper

```elm
import BackendTask
import Test
import Test.BackendTask as BackendTaskTest
import Tui
import Tui.Effect as Effect
import Tui.Screen
import Tui.Sub
import Tui.Test as TuiTest

type Msg
    = Increment
    | Quit

keyToMsg : Tui.Sub.KeyEvent -> Msg
keyToMsg event =
    case event.key of
        Tui.Sub.Character 'j' ->
            Increment

        _ ->
            Quit

app : Tui.Program () Int Msg
app =
    { data = BackendTask.succeed ()
    , init = \() -> ( 0, Effect.none )
    , update =
        \msg count ->
            case msg of
                Increment ->
                    ( count + 1, Effect.none )

                Quit ->
                    ( count, Effect.exit )
    , view = \_ count -> Tui.Screen.text ("Count: " ++ String.fromInt count)
    , subscriptions = \_ -> Tui.Sub.onKeyPress keyToMsg
    }

tuiTests : TuiTest.Test
tuiTests =
    TuiTest.describe "Counter"
        [ TuiTest.test "increments with j" <|
            TuiTest.start BackendTaskTest.init app
                |> TuiTest.pressKey 'j'
                |> TuiTest.ensureViewHas "Count: 1"
                |> TuiTest.expectRunning
        ]

suite : Test.Test
suite =
    TuiTest.toTest tuiTests
```

@docs TuiTest, Test, Outcome


## Starting a Test

Use [`start`](#start) for the default terminal size, and
[`startWithContext`](#startWithContext) when you want custom dimensions or
color profile.

Both resolve `app.data` through [`Test.BackendTask`](Test-BackendTask).

If your app uses `Tui.Sub.onResize`, the initial context is fired
automatically.

@docs start, startWithContext


## Simulating Events

Simulate user interactions in the order they would happen. Each function
threads the `TuiTest` through `update` and captures the new screen.

Prefer the user-facing helpers first (`pressKey`, `clickText`, `paste`,
`resize`). Use [`sendMsg`](#sendMsg) when you intentionally want to bypass
input routing and inject a `Msg` directly.

@docs pressKey, pressKeyWith, pressKeyN, paste, resize

@docs click, clickText, scrollDown, scrollUp, scrollDownN, scrollUpN

@docs sendMsg, advanceTime


## Resolving Effects

When your `update` returns a `Tui.Effect` that performs a `BackendTask`, the
test captures it as a pending effect instead of running it automatically.
Use [`resolveEffect`](#resolveEffect) when the pending `BackendTask` can be
resolved directly by `Test.BackendTask`.

Use [`resolveEffectWith`](#resolveEffectWith) when you need to customize the
simulation, like stubbing an HTTP response:

    |> TuiTest.resolveEffectWith
        (BackendTaskTest.simulateCommand "git" "M src/Main.elm")

@docs resolveEffect, resolveEffectWith, BackendTaskSimulator


## Screen Assertions

Assert on the plain text content of the current screen. Failed assertions
show the full screen output for easy debugging.

Use [`ensureViewHas`](#ensureViewHas) and
[`ensureViewDoesNotHave`](#ensureViewDoesNotHave) for the common case. Use
[`ensureView`](#ensureView) when you want a custom assertion, and
[`ensureModel`](#ensureModel) when the important state is not visible on
screen.

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

Every scenario ends with one of these. They finalize the pipeline into an
[`Outcome`](#Outcome).

If pending effects remain unresolved, these checks fail so you do not
accidentally ignore `BackendTask`s. Wrap the resulting outcomes with
[`test`](#test) and [`describe`](#describe), then run them through
[`toTest`](#toTest).

@docs expectRunning, expectExit, expectExitWith

@docs test, describe, toTest, done, toNamedSnapshots


## Snapshots

Every step records a snapshot automatically. `elm-pages test` reads those
snapshots and lets you step through them visually in the terminal.

Use [`toSnapshots`](#toSnapshots) for low-level inspection, and
[`withModelToString`](#withModelToString) when you also want to record model
state alongside each screen.

@docs Snapshot, toSnapshots, withModelToString

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Test as ElmTest
import Test.BackendTask as BackendTaskTest
import Test.BackendTask.Internal as BackendTaskTestInternal
import Test.Runner
import Time
import Tui exposing (Context)
import Tui.Effect as Effect exposing (Effect)
import Tui.Effect.Internal as EffectInternal
import Tui.Screen exposing (Screen)
import Tui.Screen.Internal as ScreenInternal
import Tui.Sub exposing (KeyEvent, Sub)


{-| An in-progress TUI test. Thread this through the pipeline to simulate
events and assert on screen output.
-}
type TuiTest model msg
    = TuiTest (State model msg)
    | SetupError String


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

`screen` is the `Tui.Screen.Screen` value (preserving styling), not a plain string.
Use `Tui.Screen.toString` to get plain text, or render it through the TUI pipeline
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
This resolves `app.data` through [`Test.BackendTask`](Test-BackendTask)
before the first snapshot.

Pure startup data usually uses `BackendTask.succeed`. For file, env, time, or
db-backed startup, seed the virtual environment through the `TestSetup`.

If your app subscribes to `Tui.Sub.onResize`, the initial context is fired
automatically (matching runtime behavior).

    import BackendTask
    import Test.BackendTask as BackendTaskTest
    import Tui
    import Tui.Effect as Effect
    import Tui.Screen as Screen
    import Tui.Sub
    import Tui.Test as TuiTest

    type Msg
        = Quit

    app : Tui.Program Int Int Msg
    app =
        { data = BackendTask.succeed 0
        , init = \count -> ( count, Effect.none )
        , update = \_ count -> ( count, Effect.exit )
        , view = \_ count -> Screen.text ("Count: " ++ String.fromInt count)
        , subscriptions = \_ -> Tui.Sub.onKeyPress (\_ -> Quit)
        }

    counterTest : TuiTest.TuiTest Int Msg
    counterTest =
        TuiTest.start BackendTaskTest.init app

Use [`startWithContext`](#startWithContext) for a custom terminal size.

-}
start :
    BackendTaskTest.TestSetup
    -> Tui.Program data model msg
    -> TuiTest model msg
start setup app =
    startWithContext { width = 80, height = 24, colorProfile = Tui.TrueColor } setup app


{-| Like [`start`](#start), but with a custom terminal context. Use this for
responsive layouts, small terminals, or color-profile-dependent rendering.

    import BackendTask
    import Test.BackendTask as BackendTaskTest
    import Tui
    import Tui.Effect as Effect
    import Tui.Screen as Screen
    import Tui.Sub
    import Tui.Test as TuiTest

    type Msg
        = Resized { width : Int, height : Int }

    app : Tui.Program { width : Int, height : Int } { width : Int, height : Int } Msg
    app =
        { data = BackendTask.succeed { width = 0, height = 0 }
        , init = \model -> ( model, Effect.none )
        , update =
            \msg _ ->
                case msg of
                    Resized size ->
                        ( size, Effect.none )
        , view =
            \_ size ->
                Screen.text
                    (String.fromInt size.width ++ "x" ++ String.fromInt size.height)
        , subscriptions = \_ -> Tui.Sub.onResize Resized
        }

    resizedTest : TuiTest.TuiTest { width : Int, height : Int } Msg
    resizedTest =
        TuiTest.startWithContext
            { width = 120, height = 40, colorProfile = Tui.TrueColor }
            BackendTaskTest.init
            app

If your app subscribes to `Tui.Sub.onResize`, the initial context is fired
automatically (matching runtime behavior).

-}
startWithContext :
    Context
    -> BackendTaskTest.TestSetup
    -> Tui.Program data model msg
    -> TuiTest model msg
startWithContext context setup app =
    case
        BackendTaskTest.fromBackendTaskWith setup app.data
            |> BackendTaskTestInternal.toResult
    of
        Ok resolvedData ->
            startResolvedWithContext context
                { data = resolvedData
                , init = app.init
                , update = app.update
                , view = app.view
                , subscriptions = app.subscriptions
                }

        Err errorMessage ->
            SetupError ("Failed to resolve app.data: " ++ errorMessage)


startResolvedWithContext :
    Context
    ->
        { data : data
        , init : data -> ( model, Effect msg )
        , update : msg -> model -> ( model, Effect msg )
        , view : Context -> model -> Screen
        , subscriptions : model -> Sub msg
        }
    -> TuiTest model msg
startResolvedWithContext context config =
    let
        ( initialModel, initialEffect ) =
            config.init config.data

        ( modelWithContext, contextEffect ) =
            Tui.Sub.routeEvents
                (config.subscriptions initialModel)
                (Tui.Sub.RawContext { width = context.width, height = context.height })
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



-- SIMULATING EVENTS


{-| Simulate pressing a character key with no modifiers.

    test |> TuiTest.pressKey 'j'

-}
pressKey : Char -> TuiTest model msg -> TuiTest model msg
pressKey char =
    pressKeyWith { key = Tui.Sub.Character char, modifiers = [] }


{-| Simulate pressing a character key N times.

    -- Navigate down 7 items
    test |> TuiTest.pressKeyN 7 'j'

-}
pressKeyN : Int -> Char -> TuiTest model msg -> TuiTest model msg
pressKeyN n char tuiTest =
    List.foldl (\_ acc -> pressKey char acc) tuiTest (List.range 1 n)


{-| Simulate pressing any key, including special keys and modifiers.

    test |> TuiTest.pressKeyWith { key = Tui.Sub.Arrow Tui.Sub.Down, modifiers = [] }

    test |> TuiTest.pressKeyWith { key = Tui.Sub.Character 's', modifiers = [ Tui.Sub.Ctrl ] }

-}
pressKeyWith : KeyEvent -> TuiTest model msg -> TuiTest model msg
pressKeyWith keyEvent tuiTest =
    case tuiTest of
        TuiTest state ->
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
                    Tui.Sub.routeEvents sub (Tui.Sub.RawKeyPress keyEvent)
                        |> List.foldl (applyMsg (keyEventLabel keyEvent)) (TuiTest state)

        SetupError _ ->
            tuiTest


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
paste pastedText tuiTest =
    case tuiTest of
        TuiTest state ->
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
                    Tui.Sub.routeEvents sub (Tui.Sub.RawPaste pastedText)
                        |> List.foldl
                            (applyMsg ("paste \"" ++ truncateLabel pastedText ++ "\""))
                            (TuiTest state)

        SetupError _ ->
            tuiTest


truncateLabel : String -> String
truncateLabel s =
    if String.length s > 30 then
        String.left 27 s ++ "..."

    else
        s


{-| Simulate a terminal resize. The framework handles resize automatically —
this updates the `Context` that `view` receives and routes the new size through
any `Tui.Sub.onResize` subscriptions.
-}
resize : { width : Int, height : Int } -> TuiTest model msg -> TuiTest model msg
resize size tuiTest =
    case tuiTest of
        TuiTest state ->
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
                            Tui.Sub.routeEvents
                                (state.subscriptions state.model)
                                (Tui.Sub.RawContext { width = newContext.width, height = newContext.height })
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

        SetupError _ ->
            tuiTest


{-| Simulate a left mouse click at the given row and column (0-based).

    test |> TuiTest.click { row = 3, col = 5 }

-}
click : { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
click pos =
    simulateMouseEvent
        ("click (" ++ String.fromInt pos.row ++ "," ++ String.fromInt pos.col ++ ")")
        (Tui.Sub.Click { row = pos.row, col = pos.col, button = Tui.Sub.LeftButton })


{-| Find a line containing the given text and simulate a click on it.
Like elm-program-test's `clickButton` — finds elements by content instead of
coordinates, making tests resilient to layout changes.

    test |> TuiTest.clickText "def5678"

Fails with a helpful message if the text is not found on screen.

-}
clickText : String -> TuiTest model msg -> TuiTest model msg
clickText needle tuiTest =
    case tuiTest of
        TuiTest state ->
            case ( state.error, state.exited ) of
                ( Just _, _ ) ->
                    TuiTest state

                ( _, Just _ ) ->
                    TuiTest { state | error = Just "clickText called after TUI exited" }

                ( Nothing, Nothing ) ->
                    let
                        screenLines : List String
                        screenLines =
                            Tui.Screen.toString (state.view state.context state.model)
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
                                (Tui.Sub.Click { row = match.row, col = match.col, button = Tui.Sub.LeftButton })
                                (TuiTest state)

                        Nothing ->
                            TuiTest
                                { state
                                    | error =
                                        Just
                                            ("clickText: could not find \""
                                                ++ needle
                                                ++ "\" on screen.\n\nThe screen contains:\n\n"
                                                ++ indentScreenText (Tui.Screen.toString (state.view state.context state.model))
                                            )
                                }

        SetupError _ ->
            tuiTest


{-| Simulate a scroll-down event at the given position.
-}
scrollDown : { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
scrollDown pos =
    simulateMouseEvent
        ("scrollDown (" ++ String.fromInt pos.row ++ "," ++ String.fromInt pos.col ++ ")")
        (Tui.Sub.ScrollDown { row = pos.row, col = pos.col, amount = 1 })


{-| Simulate a scroll-up event at the given position.
-}
scrollUp : { row : Int, col : Int } -> TuiTest model msg -> TuiTest model msg
scrollUp pos =
    simulateMouseEvent
        ("scrollUp (" ++ String.fromInt pos.row ++ "," ++ String.fromInt pos.col ++ ")")
        (Tui.Sub.ScrollUp { row = pos.row, col = pos.col, amount = 1 })


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


simulateMouseEvent : String -> Tui.Sub.MouseEvent -> TuiTest model msg -> TuiTest model msg
simulateMouseEvent label mouseEvent tuiTest =
    case tuiTest of
        TuiTest state ->
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
                    Tui.Sub.routeEvents sub (Tui.Sub.RawMouse mouseEvent)
                        |> List.foldl (applyMsg label) (TuiTest state)

        SetupError _ ->
            tuiTest


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
advanceTime deltaMs tuiTest =
    case tuiTest of
        TuiTest state ->
            case ( state.error, state.exited ) of
                ( Just _, _ ) ->
                    TuiTest state

                ( _, Just _ ) ->
                    TuiTest { state | error = Just "advanceTime called after TUI exited" }

                ( Nothing, Nothing ) ->
                    advanceTimeHelp (state.currentTime + deltaMs) (TuiTest state)

        SetupError _ ->
            tuiTest


advanceTimeHelp : Int -> TuiTest model msg -> TuiTest model msg
advanceTimeHelp targetTime tuiTest =
    case tuiTest of
        TuiTest state ->
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
                            Tui.Sub.getTickIntervals sub

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
                                rawEvent : Tui.Sub.RawEvent
                                rawEvent =
                                    Tui.Sub.RawTick
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
                                    Tui.Sub.routeEvents sub rawEvent

                                advancedTuiTest : TuiTest model msg
                                advancedTuiTest =
                                    List.foldl (applyMsg label) (TuiTest stateWithClock) msgs

                                label : String
                                label =
                                    "advance " ++ String.fromInt fireTime ++ "ms"
                            in
                            advanceTimeHelp targetTime advancedTuiTest

        -- BACKENDTASK SIMULATION
        SetupError _ ->
            tuiTest


{-| Resolve the next pending `BackendTask` effect with the default
`Test.BackendTask` behavior.

Use this for the common case where the pending effect can be resolved without
extra setup, for example `BackendTask.succeed`, `map`, `andThen`, or other
pure `BackendTask` flows.

    import BackendTask
    import Test.BackendTask as BackendTaskTest
    import Tui
    import Tui.Effect as Effect
    import Tui.Screen as Screen
    import Tui.Sub
    import Tui.Test as TuiTest

    type Msg
        = Fetch
        | Fetched String

    app : Tui.Program String String Msg
    app =
        { data = BackendTask.succeed "idle"
        , init = \status -> ( status, Effect.none )
        , update =
            \msg status ->
                case msg of
                    Fetch ->
                        ( status
                        , BackendTask.succeed "done"
                            |> Effect.perform Fetched
                        )

                    Fetched newStatus ->
                        ( newStatus, Effect.none )
        , view = \_ status -> Screen.text status
        , subscriptions = \_ -> Tui.Sub.onKeyPress (\_ -> Fetch)
        }

    backendTaskTest : TuiTest.TuiTest String Msg
    backendTaskTest =
        TuiTest.start BackendTaskTest.init app
            |> TuiTest.pressKey 'f'
            |> TuiTest.resolveEffect
            |> TuiTest.ensureViewHas "done"

-}
resolveEffect : TuiTest model msg -> TuiTest model msg
resolveEffect =
    resolveNextEffect BackendTaskTest.fromBackendTask


{-| Resolve the next pending `BackendTask` effect with a customized
`Test.BackendTask` simulation pipeline.

Use this when the pending effect needs extra simulation, like an HTTP
response or shell command output.

    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest
    import Tui.Test as TuiTest

    starsTest
        |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
        |> TuiTest.resolveEffectWith
            (BackendTaskTest.simulateHttpGet
                "https://api.github.com/repos/elm/core"
                (Encode.object [ ( "stargazers_count", Encode.int 7500 ) ])
            )
        |> TuiTest.ensureViewHas "Stars: 7500"

-}
resolveEffectWith :
    (BackendTaskSimulator msg -> BackendTaskSimulator msg)
    -> TuiTest model msg
    -> TuiTest model msg
resolveEffectWith simulate =
    resolveNextEffect
        (\bt ->
            bt
                |> BackendTaskTest.fromBackendTask
                |> simulate
        )


{-| The type of the `Test.BackendTask` pipeline used with
[`resolveEffectWith`](#resolveEffectWith). This is
`Test.BackendTask.Internal.BackendTaskTest` — the same type that
`Test.BackendTask` functions operate on.
-}
type alias BackendTaskSimulator msg =
    BackendTaskTestInternal.BackendTaskTest msg



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
ensureView assertion tuiTest =
    case tuiTest of
        TuiTest state ->
            case state.error of
                Just _ ->
                    TuiTest state

                Nothing ->
                    let
                        screenText : String
                        screenText =
                            Tui.Screen.toString (state.view state.context state.model)

                        result : Expectation
                        result =
                            assertion screenText
                    in
                    case getFailureMessage result of
                        Just msg ->
                            TuiTest { state | error = Just ("ensureView failed:\n" ++ msg) }

                        Nothing ->
                            TuiTest (recordAssertion "ensureView ✓" state)

        SetupError _ ->
            tuiTest


{-| Assert that the current screen contains the given text.

    test |> TuiTest.ensureViewHas "Count: 0"

-}
ensureViewHas : String -> TuiTest model msg -> TuiTest model msg
ensureViewHas needle tuiTest =
    case tuiTest of
        TuiTest state ->
            case state.error of
                Just _ ->
                    TuiTest state

                Nothing ->
                    let
                        screenText : String
                        screenText =
                            Tui.Screen.toString (state.view state.context state.model)
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

        SetupError _ ->
            tuiTest


{-| Assert that the current screen does NOT contain the given text.
-}
ensureViewDoesNotHave : String -> TuiTest model msg -> TuiTest model msg
ensureViewDoesNotHave needle tuiTest =
    case tuiTest of
        TuiTest state ->
            case state.error of
                Just _ ->
                    TuiTest state

                Nothing ->
                    let
                        screenText : String
                        screenText =
                            Tui.Screen.toString (state.view state.context state.model)
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

        SetupError _ ->
            tuiTest


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
ensureModel assertion tuiTest =
    case tuiTest of
        TuiTest state ->
            case state.error of
                Just _ ->
                    TuiTest state

                Nothing ->
                    case getFailureMessage (assertion state.model) of
                        Just msg ->
                            TuiTest { state | error = Just ("ensureModel failed:\n" ++ msg) }

                        Nothing ->
                            TuiTest state

        SetupError _ ->
            tuiTest


{-| Add an assertion label to the most recent snapshot. The stepper shows
these beneath the action label, so custom helpers can describe what they
checked without creating a new snapshot.

Use this when building companion helpers on top of [`ensureModel`](#ensureModel):

    import Expect
    import Tui.Test as TuiTest

    ensureCount : Int -> TuiTest.TuiTest Int msg -> TuiTest.TuiTest Int msg
    ensureCount expected =
        TuiTest.ensureModel (\actual -> Expect.equal expected actual)
            >> TuiTest.annotateAssertion
                ("ensureCount " ++ String.fromInt expected ++ " ✓")

-}
annotateAssertion : String -> TuiTest model msg -> TuiTest model msg
annotateAssertion description tuiTest =
    case tuiTest of
        TuiTest state ->
            case state.error of
                Just _ ->
                    TuiTest state

                Nothing ->
                    TuiTest (recordAssertion description state)

        -- STYLED TEXT ASSERTIONS
        SetupError _ ->
            tuiTest


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
ensureViewHasStyled checks needle tuiTest =
    case tuiTest of
        TuiTest state ->
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
                                Tui.Screen.toString screen
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

        SetupError _ ->
            tuiTest


{-| Assert that the screen does NOT contain the given text with ALL of the
specified style checks.

    TuiTest.test "error text is not bold" <|
        myTest
            |> TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold ] "Error"
            |> TuiTest.expectRunning

-}
ensureViewDoesNotHaveStyled : List StyleCheck -> String -> TuiTest model msg -> TuiTest model msg
ensureViewDoesNotHaveStyled checks needle tuiTest =
    case tuiTest of
        TuiTest state ->
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
                                Tui.Screen.toString screen
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

        SetupError _ ->
            tuiTest


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


tuiStyleToFlatStyle : Tui.Screen.Style -> ScreenInternal.FlatStyle
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


applyAttr : Tui.Screen.Attribute -> ScreenInternal.FlatStyle -> ScreenInternal.FlatStyle
applyAttr attr flatStyle =
    case attr of
        Tui.Screen.Bold ->
            { flatStyle | bold = True }

        Tui.Screen.Dim ->
            { flatStyle | dim = True }

        Tui.Screen.Italic ->
            { flatStyle | italic = True }

        Tui.Screen.Underline ->
            { flatStyle | underline = True }

        Tui.Screen.Strikethrough ->
            { flatStyle | strikethrough = True }

        Tui.Screen.Inverse ->
            { flatStyle | inverse = True }



-- TERMINAL ASSERTIONS


{-| Assert that the TUI is still running (has not exited).
Fails if there are unresolved pending `BackendTask` effects — use
[`resolveEffect`](#resolveEffect), [`resolveEffectWith`](#resolveEffectWith),
or [`sendMsg`](#sendMsg) to resolve them before calling this. Returns an
[`Outcome`](#Outcome) so the same scenario can be wrapped in a named
[`test`](#test) or inspected directly with [`done`](#done).
-}
expectRunning : TuiTest model msg -> Outcome
expectRunning tuiTest =
    case tuiTest of
        TuiTest state ->
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

        SetupError setupMsg ->
            Outcome { expectation = Expect.fail ("Setup failed: " ++ setupMsg), snapshots = [] }


{-| Assert that the TUI exited with code 0.
Fails if there are unresolved pending `BackendTask` effects. Returns an
[`Outcome`](#Outcome) so the same scenario can be wrapped in a named
[`test`](#test) or inspected directly with [`done`](#done).
-}
expectExit : TuiTest model msg -> Outcome
expectExit tuiTest =
    case tuiTest of
        TuiTest state ->
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

        SetupError setupMsg ->
            Outcome { expectation = Expect.fail ("Setup failed: " ++ setupMsg), snapshots = [] }


{-| Assert that the TUI exited with a specific exit code.
Fails if there are unresolved pending `BackendTask` effects. Returns an
[`Outcome`](#Outcome) so the same scenario can be wrapped in a named
[`test`](#test) or inspected directly with [`done`](#done).
-}
expectExitWith : Int -> TuiTest model msg -> Outcome
expectExitWith expectedCode tuiTest =
    case tuiTest of
        TuiTest state ->
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

        SetupError setupMsg ->
            Outcome { expectation = Expect.fail ("Setup failed: " ++ setupMsg), snapshots = [] }


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
        ++ "Use TuiTest.resolveEffect to run the next effect with the default Test.BackendTask simulation. This is the right choice even for auto-resolvable BackendTasks like BackendTask.succeed and virtual file, env, or db reads.\n\n"
        ++ "Use TuiTest.resolveEffectWith when the effect needs custom simulation (for example HTTP, commands, or custom effects), or TuiTest.sendMsg to skip the BackendTask and provide the resulting Msg directly."



-- HELPERS


applyMsg : String -> msg -> TuiTest model msg -> TuiTest model msg
applyMsg label msg tuiTest =
    case tuiTest of
        TuiTest state ->
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

        SetupError _ ->
            tuiTest


{-| Resolve the next pending BackendTask effect using a simulation function.
The simulation function takes the raw BackendTask and returns a BackendTaskTest
that has been configured with the appropriate simulation.
-}
resolveNextEffect :
    (BackendTask FatalError msg -> BackendTaskTestInternal.BackendTaskTest msg)
    -> TuiTest model msg
    -> TuiTest model msg
resolveNextEffect simulate tuiTest =
    case tuiTest of
        TuiTest state ->
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
                                        |> BackendTaskTestInternal.toResult
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

        SetupError _ ->
            tuiTest


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
withModelToString modelToString tuiTest =
    case tuiTest of
        TuiTest state ->
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

        SetupError _ ->
            tuiTest


{-| Extract the recorded snapshots from a test pipeline. Each step in the
pipeline (`start`, `resize`, `pressKey`, `resolveEffect`,
`resolveEffectWith`, `sendMsg`) records a snapshot of the screen, the action
label, and whether effects are pending.

If the pipeline encountered an error, a final snapshot with the error message
is appended so it's visible in the stepper.

Use this with the interactive test stepper to visualize a test run step by step.

-}
toSnapshots : TuiTest model msg -> List Snapshot
toSnapshots tuiTest =
    case tuiTest of
        TuiTest state ->
            case state.error of
                Just errorMsg ->
                    let
                        errorScreen : Screen
                        errorScreen =
                            Tui.Screen.text errorMsg
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

        SetupError _ ->
            []


keyEventLabel : KeyEvent -> String
keyEventLabel event =
    let
        keyName : String
        keyName =
            case event.key of
                Tui.Sub.Character c ->
                    "'" ++ String.fromChar c ++ "'"

                Tui.Sub.Enter ->
                    "Enter"

                Tui.Sub.Escape ->
                    "Escape"

                Tui.Sub.Tab ->
                    "Tab"

                Tui.Sub.Backspace ->
                    "Backspace"

                Tui.Sub.Delete ->
                    "Delete"

                Tui.Sub.Arrow dir ->
                    "Arrow "
                        ++ (case dir of
                                Tui.Sub.Up ->
                                    "Up"

                                Tui.Sub.Down ->
                                    "Down"

                                Tui.Sub.Left ->
                                    "Left"

                                Tui.Sub.Right ->
                                    "Right"
                           )

                Tui.Sub.FunctionKey n ->
                    "F" ++ String.fromInt n

                Tui.Sub.Home ->
                    "Home"

                Tui.Sub.End ->
                    "End"

                Tui.Sub.PageUp ->
                    "PageUp"

                Tui.Sub.PageDown ->
                    "PageDown"

        modPrefix : String
        modPrefix =
            event.modifiers
                |> List.map
                    (\m ->
                        case m of
                            Tui.Sub.Ctrl ->
                                "Ctrl+"

                            Tui.Sub.Alt ->
                                "Alt+"

                            Tui.Sub.Shift ->
                                "Shift+"
                    )
                |> String.concat
    in
    "pressKey " ++ modPrefix ++ keyName
