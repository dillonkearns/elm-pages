module StatusTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Status as Status


suite : Test
suite =
    describe "Tui.Status"
        [ describe "toasts"
            [ test "toast adds a message" <|
                \() ->
                    Status.init
                        |> Status.toast "Saved!"
                        |> Status.view { waiting = Nothing, tick = 0 }
                        |> Tui.toString
                        |> String.contains "Saved!"
                        |> Expect.equal True
            , test "errorToast adds an error message" <|
                \() ->
                    Status.init
                        |> Status.errorToast "Failed!"
                        |> Status.view { waiting = Nothing, tick = 0 }
                        |> Tui.toString
                        |> String.contains "Failed!"
                        |> Expect.equal True
            , test "toast auto-dismisses after enough ticks" <|
                \() ->
                    let
                        state =
                            Status.init
                                |> Status.toast "Gone soon"

                        -- Tick 21 times (toast lasts 20 ticks)
                        ticked =
                            List.range 1 21
                                |> List.foldl (\_ s -> Status.tick s) state
                    in
                    Status.view { waiting = Nothing, tick = 0 } ticked
                        |> Tui.toString
                        |> String.contains "Gone soon"
                        |> Expect.equal False
            , test "errorToast lasts longer than normal toast" <|
                \() ->
                    let
                        state =
                            Status.init
                                |> Status.errorToast "Error!"

                        -- Tick 25 times (error toast lasts 40 ticks)
                        ticked =
                            List.range 1 25
                                |> List.foldl (\_ s -> Status.tick s) state
                    in
                    Status.view { waiting = Nothing, tick = 0 } ticked
                        |> Tui.toString
                        |> String.contains "Error!"
                        |> Expect.equal True
            , test "newest toast wins (stack-based)" <|
                \() ->
                    Status.init
                        |> Status.toast "First"
                        |> Status.toast "Second"
                        |> Status.view { waiting = Nothing, tick = 0 }
                        |> Tui.toString
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "Second" |> Expect.equal True
                                    , \str -> str |> String.contains "First" |> Expect.equal False
                                    ]
                                    s
                           )
            , test "hasActivity is True when toasts exist" <|
                \() ->
                    Status.init
                        |> Status.toast "Active"
                        |> Status.hasActivity { waiting = Nothing }
                        |> Expect.equal True
            , test "hasActivity is False when no toasts" <|
                \() ->
                    Status.init
                        |> Status.hasActivity { waiting = Nothing }
                        |> Expect.equal False
            ]
        , describe "waiting status"
            [ test "waiting message shows with spinner" <|
                \() ->
                    Status.init
                        |> Status.view { waiting = Just "Pushing...", tick = 0 }
                        |> Tui.toString
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "Pushing..." |> Expect.equal True
                                    , -- Spinner character should be present
                                      \str -> str |> String.contains "|" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "spinner animates with tick" <|
                \() ->
                    let
                        view0 =
                            Status.init
                                |> Status.view { waiting = Just "Loading", tick = 0 }
                                |> Tui.toString

                        view1 =
                            Status.init
                                |> Status.view { waiting = Just "Loading", tick = 1 }
                                |> Tui.toString
                    in
                    -- Different ticks should produce different spinner frames
                    (view0 /= view1) |> Expect.equal True
            , test "waiting takes priority over toasts" <|
                \() ->
                    Status.init
                        |> Status.toast "Background message"
                        |> Status.view { waiting = Just "Working...", tick = 0 }
                        |> Tui.toString
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "Working..." |> Expect.equal True
                                    , \str -> str |> String.contains "Background message" |> Expect.equal False
                                    ]
                                    s
                           )
            , test "hasActivity is True when waiting" <|
                \() ->
                    Status.init
                        |> Status.hasActivity { waiting = Just "Working" }
                        |> Expect.equal True
            ]
        , describe "empty state"
            [ test "view returns empty when nothing active" <|
                \() ->
                    Status.init
                        |> Status.view { waiting = Nothing, tick = 0 }
                        |> Tui.toString
                        |> Expect.equal ""
            ]
        ]
