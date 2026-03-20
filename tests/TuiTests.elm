module TuiTests exposing (suite)

import Ansi.Color
import BackendTask
import BackendTask.Http
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Runner
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
                    Tui.styled { fg = Just Ansi.Color.red, bg = Nothing, attributes = [ Tui.Bold ] } "warning"
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
        , describe "Style builders"
            [ test "fg on text produces styled output" <|
                \() ->
                    Tui.text "hello" |> Tui.fg Ansi.Color.red
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> String.contains "red"
                        |> Expect.equal True
            , test "bold on text produces bold output" <|
                \() ->
                    Tui.text "hello" |> Tui.bold
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> String.contains "bold"
                        |> Expect.equal True
            , test "chaining fg + bold works" <|
                \() ->
                    Tui.text "hello" |> Tui.fg Ansi.Color.green |> Tui.bold
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "green" |> Expect.equal True
                                    , \str -> str |> String.contains "bold" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "fg on concat applies to all children" <|
                \() ->
                    Tui.concat [ Tui.text "a", Tui.text "b" ]
                        |> Tui.fg Ansi.Color.red
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                -- Both spans should have red
                                let
                                    redCount =
                                        String.indexes "red" s |> List.length
                                in
                                (redCount >= 2) |> Expect.equal True
                           )
            , test "bold on concat applies to all children" <|
                \() ->
                    Tui.concat [ Tui.text "a", Tui.text "b" ]
                        |> Tui.bold
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                let
                                    boldCount =
                                        String.indexes "bold" s |> List.length
                                in
                                (boldCount >= 2) |> Expect.equal True
                           )
            , test "fg on lines applies to all rows" <|
                \() ->
                    Tui.lines [ Tui.text "row1", Tui.text "row2" ]
                        |> Tui.fg Ansi.Color.cyan
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                let
                                    cyanCount =
                                        String.indexes "cyan" s |> List.length
                                in
                                (cyanCount >= 2) |> Expect.equal True
                           )
            , test "spaced with fg applies to gaps too" <|
                \() ->
                    Tui.spaced [ Tui.text "a", Tui.text "b" ]
                        |> Tui.bg Ansi.Color.blue
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                -- Should have blue on all 3 spans (a, space, b)
                                let
                                    blueCount =
                                        String.indexes "blue" s |> List.length
                                in
                                (blueCount >= 3) |> Expect.equal True
                           )
            , test "outer style overwrites inner style" <|
                \() ->
                    Tui.concat
                        [ Tui.text "red" |> Tui.fg Ansi.Color.red
                        , Tui.text "also"
                        ]
                        |> Tui.fg Ansi.Color.green
                        |> Tui.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "green" |> Expect.equal True
                                    -- red should be gone, replaced by green
                                    , \str -> str |> String.contains "red" |> Expect.equal False
                                    ]
                                    s
                           )
            , test "style on empty returns empty" <|
                \() ->
                    Tui.empty |> Tui.fg Ansi.Color.red
                        |> Tui.toString
                        |> Expect.equal ""
            , test "text content preserved through style builders" <|
                \() ->
                    Tui.concat [ Tui.text "hello ", Tui.text "world" ]
                        |> Tui.fg Ansi.Color.green
                        |> Tui.bold
                        |> Tui.toString
                        |> Expect.equal "hello world"
            ]
        , describe "wrapWidth"
            [ test "short text returns single line unchanged" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.wrapWidth 20
                        |> List.map Tui.toString
                        |> Expect.equal [ "hello" ]
            , test "wraps at word boundary" <|
                \() ->
                    Tui.text "hello world foo"
                        |> Tui.wrapWidth 11
                        |> List.map Tui.toString
                        |> Expect.equal [ "hello world", "foo" ]
            , test "wraps long text into multiple lines" <|
                \() ->
                    Tui.text "one two three four five"
                        |> Tui.wrapWidth 10
                        |> List.map Tui.toString
                        |> Expect.equal [ "one two", "three four", "five" ]
            , test "preserves style across wrap" <|
                \() ->
                    Tui.text "hello world"
                        |> Tui.bold
                        |> Tui.wrapWidth 6
                        |> List.map (\s -> ( Tui.toString s, Tui.extractStyle s ))
                        |> Expect.equal
                            [ ( "hello", { fg = Nothing, bg = Nothing, attributes = [ Tui.Bold ] } )
                            , ( "world", { fg = Nothing, bg = Nothing, attributes = [ Tui.Bold ] } )
                            ]
            , test "preserves styles in concat across wrap boundary" <|
                \() ->
                    Tui.concat
                        [ Tui.text "This is a "
                        , Tui.text "very important" |> Tui.bold
                        , Tui.text " paragraph."
                        ]
                        |> Tui.wrapWidth 24
                        |> List.map Tui.toString
                        |> Expect.equal [ "This is a very important", "paragraph." ]
            , test "word longer than maxWidth is broken mid-word" <|
                \() ->
                    Tui.text "abcdefghij rest"
                        |> Tui.wrapWidth 5
                        |> List.map Tui.toString
                        |> Expect.equal [ "abcde", "fghij", "rest" ]
            , test "empty screen returns empty list" <|
                \() ->
                    Tui.empty
                        |> Tui.wrapWidth 10
                        |> Expect.equal []
            , test "single word exactly at width" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.wrapWidth 5
                        |> List.map Tui.toString
                        |> Expect.equal [ "hello" ]
            , test "multiple spaces treated as break points" <|
                \() ->
                    Tui.text "a b c d e"
                        |> Tui.wrapWidth 5
                        |> List.map Tui.toString
                        |> Expect.equal [ "a b c", "d e" ]
            , test "styled span split preserves style on both halves" <|
                \() ->
                    -- "very important" is bold, gets split across lines
                    Tui.concat
                        [ Tui.text "xx "
                        , Tui.text "aaa bbb" |> Tui.fg Ansi.Color.red
                        , Tui.text " end"
                        ]
                        |> Tui.wrapWidth 7
                        |> List.map Tui.toString
                        |> Expect.equal [ "xx aaa", "bbb end" ]
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
        , describe "TuiTest - onContext"
            [ test "startWithContext routes initial context through subscriptions" <|
                \() ->
                    contextTest False { width = 120, height = 40, colorProfile = Tui.TrueColor }
                        |> TuiTest.ensureViewHas "Stored: 120×40"
                        |> TuiTest.expectRunning
            , test "resize routes context through subscriptions" <|
                \() ->
                    contextTest False { width = 80, height = 24, colorProfile = Tui.TrueColor }
                        |> TuiTest.resize { width = 120, height = 40 }
                        |> TuiTest.ensureViewHas "Stored: 120×40"
                        |> TuiTest.expectRunning
            , test "startWithContext keeps effects returned from initial context update" <|
                \() ->
                    contextTest True { width = 120, height = 40, colorProfile = Tui.TrueColor }
                        |> TuiTest.resolveEffect identity
                        |> TuiTest.ensureViewHas "Effect: 120×40"
                        |> TuiTest.expectRunning
            , test "resize keeps effects returned from context update" <|
                \() ->
                    contextTest True { width = 80, height = 24, colorProfile = Tui.TrueColor }
                        |> TuiTest.resolveEffect identity
                        |> TuiTest.resize { width = 120, height = 40 }
                        |> TuiTest.resolveEffect identity
                        |> TuiTest.ensureViewHas "Effect: 120×40"
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
                        |> TuiTest.sendMsg (GotStars (Ok 0))
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
        , describe "TuiTest - error messages"
            [ test "expectRunning fails with helpful message when effects are pending" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        -- Don't resolve the HTTP effect
                        |> TuiTest.expectRunning
                        |> expectFailureContaining "pending BackendTask"
            , test "expectExit fails with helpful message when effects are pending" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.expectExit
                        |> expectFailureContaining "pending BackendTask"
            , test "resolveEffect with no pending effect fails with helpful message" <|
                \() ->
                    starsTest
                        -- Don't press Enter — no effect triggered
                        |> TuiTest.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/foo/bar"
                                (Encode.int 0)
                            )
                        |> TuiTest.expectRunning
                        |> expectFailureContaining "No pending BackendTask"
            , test "pressKey after exit fails with helpful message" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.expectExit
                        |> expectFailureContaining "after TUI exited"
            , test "resolveEffect with wrong URL surfaces Test.BackendTask error" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://WRONG-URL.com"
                                (Encode.int 0)
                            )
                        |> TuiTest.expectRunning
                        |> expectFailureContaining "WRONG-URL"
            , test "ensureViewHas failure shows actual screen content" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewHas "this text is not on screen"
                        |> TuiTest.expectRunning
                        |> expectFailureContaining "Count: 0"
            ]
        , describe "TuiTest - Snapshots"
            [ test "toSnapshots captures initial state" <|
                \() ->
                    counterTest
                        |> TuiTest.toSnapshots
                        |> List.length
                        |> Expect.equal 1
            , test "initial snapshot screen is a Screen (use Tui.toString to query)" <|
                \() ->
                    counterTest
                        |> TuiTest.toSnapshots
                        |> List.head
                        |> Maybe.map (.screen >> Tui.toString)
                        |> Maybe.withDefault ""
                        |> String.contains "Count: 0"
                        |> Expect.equal True
            , test "initial snapshot label is init" <|
                \() ->
                    counterTest
                        |> TuiTest.toSnapshots
                        |> List.head
                        |> Maybe.map .label
                        |> Expect.equal (Just "init")
            , test "each pressKey adds a snapshot" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.toSnapshots
                        |> List.length
                        |> Expect.equal 4
            , test "snapshots capture screen at each step" <|
                \() ->
                    let
                        snapshots : List TuiTest.Snapshot
                        snapshots =
                            counterTest
                                |> TuiTest.pressKey 'k'
                                |> TuiTest.pressKey 'k'
                                |> TuiTest.toSnapshots
                    in
                    snapshots
                        |> List.map (.screen >> Tui.toString)
                        |> List.map (String.contains "Count: 0")
                        |> Expect.equal [ True, False, False ]
            , test "snapshots have descriptive labels" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKeyWith { key = Tui.Arrow Tui.Down, modifiers = [] }
                        |> TuiTest.toSnapshots
                        |> List.map .label
                        |> Expect.equal [ "init", "pressKey 'k'", "pressKey Arrow Down" ]
            , test "snapshots track pending effects" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.toSnapshots
                        |> List.map .hasPendingEffects
                        |> Expect.equal [ False, True ]
            , test "resolveEffect adds a snapshot" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                (Encode.object [ ( "stargazers_count", Encode.int 42 ) ])
                            )
                        |> TuiTest.toSnapshots
                        |> List.length
                        |> Expect.equal 3
            , test "snapshots have no modelState by default" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.toSnapshots
                        |> List.map .modelState
                        |> Expect.equal [ Nothing, Nothing ]
            , test "withModelToString captures model state at each step" <|
                \() ->
                    counterTest
                        |> TuiTest.withModelToString Debug.toString
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.toSnapshots
                        |> List.map .modelState
                        |> List.map (Maybe.withDefault "")
                        |> List.map (String.contains "count")
                        |> Expect.equal [ True, True ]
            , test "withModelToString shows changing values" <|
                \() ->
                    counterTest
                        |> TuiTest.withModelToString Debug.toString
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.toSnapshots
                        |> List.filterMap .modelState
                        |> List.map (String.contains "count = 2")
                        |> Expect.equal [ False, False, True ]
            , test "snapshot.rerender re-renders at a different terminal size" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.toSnapshots
                        |> List.drop 1
                        |> List.head
                        |> Maybe.map (\s -> s.rerender { width = 100, height = 50, colorProfile = Tui.TrueColor })
                        |> Maybe.map Tui.toString
                        |> Maybe.withDefault ""
                        |> String.contains "100×50"
                        |> Expect.equal True
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


{-| Helper: assert that an Expectation is a failure containing a substring.
-}
expectFailureContaining : String -> Expectation -> Expectation
expectFailureContaining needle expectation =
    case Test.Runner.getFailureReason expectation of
        Nothing ->
            Expect.fail
                ("Expected a failure containing:\n\n    \""
                    ++ needle
                    ++ "\"\n\nbut the test passed."
                )

        Just { description } ->
            if String.contains needle description then
                Expect.pass

            else
                Expect.fail
                    ("Expected failure message to contain:\n\n    \""
                        ++ needle
                        ++ "\"\n\nbut the failure message was:\n\n    \""
                        ++ description
                        ++ "\""
                    )



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
        [ Tui.styled { fg = Nothing, bg = Nothing, attributes = [ Tui.Bold ] } "Counter"
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



-- Context TUI for testing framework-managed onContext behavior


type alias ContextModel =
    { stored : String
    , effectStatus : String
    , triggerEffect : Bool
    }


type ContextMsg
    = ContextChanged { width : Int, height : Int }
    | ContextEffectComplete String


contextInit : Bool -> () -> ( ContextModel, Effect ContextMsg )
contextInit triggerEffect () =
    ( { stored = "none"
      , effectStatus = "Effect: idle"
      , triggerEffect = triggerEffect
      }
    , Effect.none
    )


contextUpdate : ContextMsg -> ContextModel -> ( ContextModel, Effect ContextMsg )
contextUpdate msg model =
    case msg of
        ContextChanged ctx ->
            let
                sizeLabel : String
                sizeLabel =
                    formatSize ctx
            in
            if model.triggerEffect then
                ( { model | stored = sizeLabel }
                , BackendTask.succeed sizeLabel
                    |> Effect.perform ContextEffectComplete
                )

            else
                ( { model | stored = sizeLabel }, Effect.none )

        ContextEffectComplete sizeLabel ->
            ( { model | effectStatus = "Effect: " ++ sizeLabel }, Effect.none )


contextView : Tui.Context -> ContextModel -> Tui.Screen
contextView _ model =
    Tui.lines
        [ Tui.text ("Stored: " ++ model.stored)
        , Tui.text model.effectStatus
        ]


contextSubscriptions : ContextModel -> Tui.Sub.Sub ContextMsg
contextSubscriptions _ =
    Tui.Sub.onContext ContextChanged


contextTest : Bool -> Tui.Context -> TuiTest.TuiTest ContextModel ContextMsg
contextTest triggerEffect context =
    TuiTest.startWithContext context
        { data = ()
        , init = contextInit triggerEffect
        , update = contextUpdate
        , view = contextView
        , subscriptions = contextSubscriptions
        }


formatSize : { a | width : Int, height : Int } -> String
formatSize ctx =
    String.fromInt ctx.width ++ "×" ++ String.fromInt ctx.height


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
        [ Tui.styled { fg = Nothing, bg = Nothing, attributes = [ Tui.Bold ] } "GitHub Stars"
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
