module ToastTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Toast as Toast


suite : Test
suite =
    describe "Tui.Toast"
        [ describe "init"
            [ test "no toasts initially" <|
                \() ->
                    Toast.init
                        |> Toast.hasToasts
                        |> Expect.equal False
            , test "view returns empty when no toasts" <|
                \() ->
                    Toast.init
                        |> Toast.view
                        |> Tui.toString
                        |> Expect.equal ""
            ]
        , describe "toast"
            [ test "toast adds a message" <|
                \() ->
                    Toast.init
                        |> Toast.toast "Committed!"
                        |> Toast.hasToasts
                        |> Expect.equal True
            , test "toast message appears in view" <|
                \() ->
                    Toast.init
                        |> Toast.toast "Committed!"
                        |> Toast.view
                        |> Tui.toString
                        |> String.contains "Committed!"
                        |> Expect.equal True
            , test "newest toast wins (shown on top)" <|
                \() ->
                    Toast.init
                        |> Toast.toast "First"
                        |> Toast.toast "Second"
                        |> Toast.view
                        |> Tui.toString
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "Second" |> Expect.equal True
                                    , \str -> str |> String.contains "First" |> Expect.equal False
                                    ]
                                    s
                           )
            ]
        , describe "errorToast"
            [ test "error toast appears in view" <|
                \() ->
                    Toast.init
                        |> Toast.errorToast "Failed!"
                        |> Toast.view
                        |> Tui.toString
                        |> String.contains "Failed!"
                        |> Expect.equal True
            ]
        , describe "tick (auto-dismiss)"
            [ test "toast dismisses after enough ticks" <|
                \() ->
                    let
                        state : Toast.State
                        state =
                            Toast.init
                                |> Toast.toast "Bye"

                        -- Tick 20 times (normal toast = 20 ticks)
                        dismissed : Toast.State
                        dismissed =
                            List.range 1 20
                                |> List.foldl (\_ s -> Toast.tick s) state
                    in
                    Toast.hasToasts dismissed
                        |> Expect.equal False
            , test "toast still visible before dismissal" <|
                \() ->
                    let
                        state : Toast.State
                        state =
                            Toast.init
                                |> Toast.toast "Still here"

                        -- Tick 10 times (half of 20)
                        partway : Toast.State
                        partway =
                            List.range 1 10
                                |> List.foldl (\_ s -> Toast.tick s) state
                    in
                    Expect.all
                        [ \s -> Toast.hasToasts s |> Expect.equal True
                        , \s -> Toast.view s |> Tui.toString |> String.contains "Still here" |> Expect.equal True
                        ]
                        partway
            , test "error toast takes longer to dismiss (40 ticks)" <|
                \() ->
                    let
                        state : Toast.State
                        state =
                            Toast.init
                                |> Toast.errorToast "Error!"

                        -- Tick 20 times (not enough for error)
                        partway : Toast.State
                        partway =
                            List.range 1 20
                                |> List.foldl (\_ s -> Toast.tick s) state

                        -- Tick 40 times total
                        dismissed : Toast.State
                        dismissed =
                            List.range 1 40
                                |> List.foldl (\_ s -> Toast.tick s) state
                    in
                    Expect.all
                        [ \_ -> Toast.hasToasts partway |> Expect.equal True
                        , \_ -> Toast.hasToasts dismissed |> Expect.equal False
                        ]
                        ()
            , test "older toast survives after newer one dismissed" <|
                \() ->
                    let
                        state : Toast.State
                        state =
                            Toast.init
                                |> Toast.errorToast "Long error"
                                |> Toast.toast "Short notice"

                        -- Tick 20 times — short notice dismissed, error remains
                        afterShortDismissed : Toast.State
                        afterShortDismissed =
                            List.range 1 20
                                |> List.foldl (\_ s -> Toast.tick s) state
                    in
                    Expect.all
                        [ \s -> Toast.hasToasts s |> Expect.equal True
                        , \s -> Toast.view s |> Tui.toString |> String.contains "Long error" |> Expect.equal True
                        ]
                        afterShortDismissed
            ]
        ]
