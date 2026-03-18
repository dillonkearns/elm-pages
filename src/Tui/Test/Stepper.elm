module Tui.Test.Stepper exposing (run, runNamed)

{-| Run a TUI test pipeline as an interactive stepper. Used by `elm-pages test`.

The stepper displays each snapshot from a `TuiTest` pipeline and lets you
navigate with arrow keys to step through the test.

@docs run, runNamed

-}

import Ansi.Color
import BackendTask
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Sub
import Tui.Test as TuiTest


{-| Create a stepper Script from a TuiTest pipeline.

    module MyTuiTest exposing (run)

    import Tui.Test as TuiTest
    import Tui.Test.Stepper

    run =
        myTuiTest
            |> TuiTest.withModelToString Debug.toString
            |> TuiTest.pressKey 'j'
            |> TuiTest.pressKey 'k'
            |> Tui.Test.Stepper.run

-}
run : TuiTest.TuiTest model msg -> Script
run tuiTest =
    let
        snapshots : List TuiTest.Snapshot
        snapshots =
            TuiTest.toSnapshots tuiTest
    in
    Script.tui
        { data = BackendTask.succeed snapshots
        , init = stepperInit
        , update = stepperUpdate
        , view = stepperView
        , subscriptions = stepperSubscriptions
        }


{-| Create a stepper Script from named test pipelines. Used by `elm-pages test`
which auto-discovers `TuiTest` values and passes their snapshots.

    Tui.Test.Stepper.runNamed
        [ ( "myTest", Tui.Test.toSnapshots myTest )
        , ( "otherTest", Tui.Test.toSnapshots otherTest )
        ]

If multiple tests are provided, the stepper shows a title with the test name
and Tab cycles between tests.

-}
runNamed : List ( String, List TuiTest.Snapshot ) -> Script
runNamed namedTests =
    let
        allTests : List { name : String, snapshots : List TuiTest.Snapshot }
        allTests =
            namedTests
                |> List.map (\( name, snapshots ) -> { name = name, snapshots = snapshots })
    in
    Script.tui
        { data = BackendTask.succeed allTests
        , init = namedStepperInit
        , update = namedStepperUpdate
        , view = namedStepperView
        , subscriptions = stepperSubscriptions
        }


type alias StepperModel =
    { snapshots : List TuiTest.Snapshot
    , currentIndex : Int
    , allTests : List { name : String, snapshots : List TuiTest.Snapshot }
    , currentTestIndex : Int
    }


type StepperMsg
    = KeyPressed Tui.KeyEvent


stepperInit : List TuiTest.Snapshot -> ( StepperModel, Effect.Effect StepperMsg )
stepperInit snapshots =
    ( { snapshots = snapshots
      , currentIndex = 0
      , allTests = [ { name = "test", snapshots = snapshots } ]
      , currentTestIndex = 0
      }
    , Effect.none
    )


namedStepperInit : List { name : String, snapshots : List TuiTest.Snapshot } -> ( StepperModel, Effect.Effect StepperMsg )
namedStepperInit tests =
    let
        firstSnapshots : List TuiTest.Snapshot
        firstSnapshots =
            tests
                |> List.head
                |> Maybe.map .snapshots
                |> Maybe.withDefault []
    in
    ( { snapshots = firstSnapshots
      , currentIndex = 0
      , allTests = tests
      , currentTestIndex = 0
      }
    , Effect.none
    )


stepperUpdate : StepperMsg -> StepperModel -> ( StepperModel, Effect.Effect StepperMsg )
stepperUpdate msg model =
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Arrow Tui.Right ->
                    ( { model
                        | currentIndex =
                            min (List.length model.snapshots - 1) (model.currentIndex + 1)
                      }
                    , Effect.none
                    )

                Tui.Arrow Tui.Left ->
                    ( { model
                        | currentIndex = max 0 (model.currentIndex - 1)
                      }
                    , Effect.none
                    )

                Tui.Tab ->
                    switchToNextTest model

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )


namedStepperUpdate : StepperMsg -> StepperModel -> ( StepperModel, Effect.Effect StepperMsg )
namedStepperUpdate =
    stepperUpdate


namedStepperView : Tui.Context -> StepperModel -> Tui.Screen
namedStepperView =
    stepperView


switchToNextTest : StepperModel -> ( StepperModel, Effect.Effect StepperMsg )
switchToNextTest model =
    if List.length model.allTests <= 1 then
        ( model, Effect.none )

    else
        let
            nextIndex : Int
            nextIndex =
                modBy (List.length model.allTests) (model.currentTestIndex + 1)

            nextSnapshots : List TuiTest.Snapshot
            nextSnapshots =
                model.allTests
                    |> List.drop nextIndex
                    |> List.head
                    |> Maybe.map .snapshots
                    |> Maybe.withDefault []
        in
        ( { model
            | currentTestIndex = nextIndex
            , snapshots = nextSnapshots
            , currentIndex = 0
          }
        , Effect.none
        )


stepperView : Tui.Context -> StepperModel -> Tui.Screen
stepperView ctx model =
    let
        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.Dim ] }

        maybeSnapshot : Maybe TuiTest.Snapshot
        maybeSnapshot =
            model.snapshots
                |> List.drop model.currentIndex
                |> List.head
    in
    case maybeSnapshot of
        Just snapshot ->
            let
                headerStyle : Tui.Style
                headerStyle =
                    { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.Bold ] }

                separator : String
                separator =
                    String.repeat (ctx.width - 4) "─"

                headerText : String
                headerText =
                    if List.length model.allTests > 1 then
                        let
                            testName : String
                            testName =
                                model.allTests
                                    |> List.drop model.currentTestIndex
                                    |> List.head
                                    |> Maybe.map .name
                                    |> Maybe.withDefault "test"
                        in
                        "  " ++ testName ++ " — Step " ++ String.fromInt (model.currentIndex + 1) ++ " of " ++ String.fromInt (List.length model.snapshots)

                    else
                        "  Test Stepper — Step " ++ String.fromInt (model.currentIndex + 1) ++ " of " ++ String.fromInt (List.length model.snapshots)

                footerText : String
                footerText =
                    if List.length model.allTests > 1 then
                        "  ← → navigate   Tab next test   q quit"

                    else
                        "  ← → navigate   q quit"

                stepIndicator : Tui.Screen
                stepIndicator =
                    Tui.concat
                        (model.snapshots
                            |> List.indexedMap
                                (\i snapshotForIndicator ->
                                    if i == model.currentIndex then
                                        Tui.styled
                                            { fg = Just Ansi.Color.cyan
                                            , bg = Nothing
                                            , attributes = [ Tui.Bold ]
                                            }
                                            (" ● " ++ snapshotForIndicator.label ++ " ")

                                    else
                                        Tui.styled dimStyle " ○ "
                                )
                        )
            in
            Tui.lines
                ([ Tui.styled headerStyle headerText
                 , Tui.text ""
                 , Tui.concat
                    [ Tui.styled dimStyle "  Action: "
                    , Tui.styled
                        { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [ Tui.Bold ] }
                        snapshot.label
                    , if snapshot.hasPendingEffects then
                        Tui.styled
                            { fg = Just Ansi.Color.magenta, bg = Nothing, attributes = [] }
                            "  ⟳ pending effect"

                      else
                        Tui.empty
                    ]
                 , Tui.text ""
                 , Tui.styled dimStyle ("  " ++ separator)
                 , Tui.text ""
                 ]
                    ++ (snapshot.screen
                            |> Tui.toScreenLines
                            |> List.map
                                (\line ->
                                    Tui.concat
                                        [ Tui.styled dimStyle "  │ "
                                        , line
                                        ]
                                )
                       )
                    ++ [ Tui.text ""
                       , Tui.styled dimStyle ("  " ++ separator)
                       , case snapshot.modelState of
                            Just modelStr ->
                                Tui.lines
                                    [ Tui.text ""
                                    , Tui.styled
                                        { fg = Just Ansi.Color.green
                                        , bg = Nothing
                                        , attributes = [ Tui.Bold ]
                                        }
                                        "  Model:"
                                    , modelStr
                                        |> String.lines
                                        |> List.map (\line -> Tui.styled dimStyle ("    " ++ line))
                                        |> Tui.lines
                                    ]

                            Nothing ->
                                Tui.empty
                       , Tui.text ""
                       , stepIndicator
                       , Tui.text ""
                       , Tui.styled dimStyle footerText
                       ]
                )

        Nothing ->
            Tui.styled dimStyle "  No snapshots"


stepperSubscriptions : StepperModel -> Tui.Sub.Sub StepperMsg
stepperSubscriptions _ =
    Tui.Sub.onKeyPress KeyPressed
