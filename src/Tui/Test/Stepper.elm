module Tui.Test.Stepper exposing (run)

{-| Run a TUI test pipeline as an interactive stepper. Used by `elm-pages test`.

The stepper displays each snapshot from a `TuiTest` pipeline and lets you
navigate with arrow keys to step through the test.

@docs run

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


type alias StepperModel =
    { snapshots : List TuiTest.Snapshot
    , currentIndex : Int
    }


type StepperMsg
    = KeyPressed Tui.KeyEvent


stepperInit : List TuiTest.Snapshot -> ( StepperModel, Effect.Effect StepperMsg )
stepperInit snapshots =
    ( { snapshots = snapshots
      , currentIndex = 0
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

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )


stepperView : Tui.Context -> StepperModel -> Tui.Screen
stepperView ctx model =
    let
        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }

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
                    { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.bold ] }

                separator : String
                separator =
                    String.repeat (ctx.width - 4) "─"

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
                                            , attributes = [ Tui.bold ]
                                            }
                                            (" ● " ++ snapshotForIndicator.label ++ " ")

                                    else
                                        Tui.styled dimStyle " ○ "
                                )
                        )
            in
            Tui.lines
                ([ Tui.styled headerStyle
                    ("  Test Stepper — Step "
                        ++ String.fromInt (model.currentIndex + 1)
                        ++ " of "
                        ++ String.fromInt (List.length model.snapshots)
                    )
                 , Tui.text ""
                 , Tui.concat
                    [ Tui.styled dimStyle "  Action: "
                    , Tui.styled
                        { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [ Tui.bold ] }
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
                            |> Tui.toLines
                            |> List.map
                                (\line ->
                                    Tui.concat
                                        [ Tui.styled dimStyle "  │ "
                                        , Tui.text line
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
                                        , attributes = [ Tui.bold ]
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
                       , Tui.styled dimStyle "  ← → navigate   q quit"
                       ]
                )

        Nothing ->
            Tui.styled dimStyle "  No snapshots"


stepperSubscriptions : StepperModel -> Tui.Sub.Sub StepperMsg
stepperSubscriptions _ =
    Tui.Sub.onKeyPress KeyPressed
