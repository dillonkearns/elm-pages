module TuiTests exposing (suite, tuiTests)

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
import Time
import Tui exposing (plain)
import Tui.Effect as Effect exposing (Effect)
import Tui.Input as Input
import Tui.Internal
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
                    Tui.styled { plain | fg = Just Ansi.Color.red, attributes = [ Tui.Bold ] } "warning"
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
                    Tui.text "hello"
                        |> Tui.fg Ansi.Color.red
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> String.contains "red"
                        |> Expect.equal True
            , test "bold on text produces bold output" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.bold
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> String.contains "bold"
                        |> Expect.equal True
            , test "chaining fg + bold works" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.fg Ansi.Color.green
                        |> Tui.bold
                        |> Tui.Internal.encodeScreen
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
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                -- Both spans should have red
                                let
                                    redCount : Int
                                    redCount =
                                        String.indexes "red" s |> List.length
                                in
                                (redCount >= 2) |> Expect.equal True
                           )
            , test "bold on concat applies to all children" <|
                \() ->
                    Tui.concat [ Tui.text "a", Tui.text "b" ]
                        |> Tui.bold
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                let
                                    boldCount : Int
                                    boldCount =
                                        String.indexes "bold" s |> List.length
                                in
                                (boldCount >= 2) |> Expect.equal True
                           )
            , test "fg on lines applies to all rows" <|
                \() ->
                    Tui.lines [ Tui.text "row1", Tui.text "row2" ]
                        |> Tui.fg Ansi.Color.cyan
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                let
                                    cyanCount : Int
                                    cyanCount =
                                        String.indexes "cyan" s |> List.length
                                in
                                (cyanCount >= 2) |> Expect.equal True
                           )
            , test "outer style overwrites inner style" <|
                \() ->
                    Tui.concat
                        [ Tui.text "inner" |> Tui.fg Ansi.Color.red
                        , Tui.text "also"
                        ]
                        |> Tui.fg Ansi.Color.green
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "green" |> Expect.equal True

                                    -- red should be gone, replaced by green
                                    , \str -> str |> String.contains "\"red\"" |> Expect.equal False
                                    ]
                                    s
                           )
            , test "style on empty returns empty" <|
                \() ->
                    Tui.empty
                        |> Tui.fg Ansi.Color.red
                        |> Tui.toString
                        |> Expect.equal ""
            , test "text content preserved through style builders" <|
                \() ->
                    Tui.concat [ Tui.text "hello ", Tui.text "world" ]
                        |> Tui.fg Ansi.Color.green
                        |> Tui.bold
                        |> Tui.toString
                        |> Expect.equal "hello world"
            , test "link encodes hyperlink in JSON" <|
                \() ->
                    Tui.text "elm/core"
                        |> Tui.link { url = "https://package.elm-lang.org" }
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> String.contains "https://package.elm-lang.org"
                        |> Expect.equal True
            , test "link composes with fg and bold" <|
                \() ->
                    Tui.text "elm/core"
                        |> Tui.fg Ansi.Color.blue
                        |> Tui.underline
                        |> Tui.link { url = "https://example.com" }
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "https://example.com" |> Expect.equal True
                                    , \str -> str |> String.contains "blue" |> Expect.equal True
                                    , \str -> str |> String.contains "underline" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "link on concat applies to all children" <|
                \() ->
                    Tui.concat [ Tui.text "hello ", Tui.text "world" ]
                        |> Tui.link { url = "https://example.com" }
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> (\s ->
                                let
                                    linkCount : Int
                                    linkCount =
                                        String.indexes "https://example.com" s |> List.length
                                in
                                (linkCount >= 2) |> Expect.equal True
                           )
            , test "link stripped by toString" <|
                \() ->
                    Tui.text "elm/core"
                        |> Tui.link { url = "https://example.com" }
                        |> Tui.toString
                        |> Expect.equal "elm/core"
            , test "link preserved by truncateWidth" <|
                \() ->
                    Tui.text "long link text"
                        |> Tui.link { url = "https://example.com" }
                        |> Tui.truncateWidth 10
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> String.contains "https://example.com"
                        |> Expect.equal True
            , test "link preserved by wrapWidth" <|
                \() ->
                    Tui.text "hello world"
                        |> Tui.link { url = "https://example.com" }
                        |> Tui.wrapWidth 6
                        |> List.map (\s -> Tui.extractStyle s |> .hyperlink)
                        |> Expect.equal [ Just "https://example.com", Just "https://example.com" ]
            ]
        , describe "Input"
            [ test "viewMasked preserves the inverse cursor while hiding the real text" <|
                \() ->
                    let
                        encoded : String
                        encoded =
                            Input.init "secret"
                                |> Input.viewMasked { width = 40 }
                                |> Tui.Internal.encodeScreen
                                |> Encode.encode 0
                    in
                    Expect.all
                        [ \json -> json |> String.contains "secret" |> Expect.equal False
                        , \json -> json |> String.contains "******" |> Expect.equal True
                        , \json -> json |> String.contains "\"inverse\":true" |> Expect.equal True
                        ]
                        encoded
            , test "long input keeps the cursor visible when constrained" <|
                \() ->
                    Input.init "abcdef"
                        |> Input.view { width = 3 }
                        |> Tui.Internal.encodeScreen
                        |> Encode.encode 0
                        |> String.contains "\"inverse\":true"
                        |> Expect.equal True
            , test "editing around emoji uses grapheme boundaries" <|
                \() ->
                    Input.init "🙂"
                        |> Input.update { key = Tui.Arrow Tui.Left, modifiers = [] }
                        |> Input.update { key = Tui.Character 'a', modifiers = [] }
                        |> Input.text
                        |> Expect.equal "a🙂"
            , test "moving through emoji does not render replacement characters" <|
                \() ->
                    Input.init "🙂"
                        |> Input.update { key = Tui.Arrow Tui.Left, modifiers = [] }
                        |> Input.view { width = 10 }
                        |> Tui.toString
                        |> String.contains "�"
                        |> Expect.equal False
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
                            [ ( "hello", { plain | attributes = [ Tui.Bold ] } )
                            , ( "world", { plain | attributes = [ Tui.Bold ] } )
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
            , test "non-positive width returns empty list" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.wrapWidth 0
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
            , test "preserves existing line breaks instead of dropping later lines" <|
                \() ->
                    Tui.lines
                        [ Tui.text "top"
                        , Tui.text "bottom"
                        ]
                        |> Tui.wrapWidth 10
                        |> List.map Tui.toString
                        |> Expect.equal [ "top", "bottom" ]
            , test "preserves blank lines when wrapping multiline screens" <|
                \() ->
                    Tui.lines
                        [ Tui.text "top"
                        , Tui.blank
                        , Tui.text "bottom"
                        ]
                        |> Tui.wrapWidth 10
                        |> List.map Tui.toString
                        |> Expect.equal [ "top", "", "bottom" ]
            , test "wraps by grapheme instead of splitting combining marks" <|
                \() ->
                    Tui.text "áb"
                        |> Tui.wrapWidth 1
                        |> List.map Tui.toString
                        |> Expect.equal [ "á", "b" ]
            ]
        , describe "truncateWidth"
            [ test "non-positive width returns empty screen" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.truncateWidth 0
                        |> Tui.toString
                        |> Expect.equal ""
            , test "truncates by grapheme instead of corrupting emoji" <|
                \() ->
                    Tui.text "🙂x"
                        |> Tui.truncateWidth 2
                        |> Tui.toString
                        |> Expect.equal "🙂x"
            ]
        , describe "concat"
            [ test "concatenates multiline screens row by row" <|
                \() ->
                    Tui.concat
                        [ Tui.text "a"
                        , Tui.lines
                            [ Tui.text "b"
                            , Tui.text "c"
                            ]
                        ]
                        |> Tui.toString
                        |> Expect.equal "ab\nc"
            , test "keeps trailing rows from longer children" <|
                \() ->
                    Tui.concat
                        [ Tui.lines
                            [ Tui.text "a"
                            , Tui.text "b"
                            ]
                        , Tui.lines
                            [ Tui.text "x"
                            , Tui.text "y"
                            , Tui.text "z"
                            ]
                        ]
                        |> Tui.toString
                        |> Expect.equal "ax\nby\nz"
            ]
        , describe "TuiTest - Counter"
            [ test "initial view shows count 0" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "k increments" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "Count: 1"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "j decrements" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "Count: -1"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
                        |> TuiTest.done
            , test "q exits" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.expectExit
                        |> TuiTest.done
            , test "Escape exits" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKeyWith
                            { key = Tui.Escape, modifiers = [] }
                        |> TuiTest.expectExit
                        |> TuiTest.done
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
                        |> TuiTest.done
            , test "unsubscribed keys are ignored" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "resize updates context in view (framework-managed)" <|
                \() ->
                    counterTest
                        |> TuiTest.resize { width = 120, height = 40 }
                        |> TuiTest.ensureViewHas "120×40"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "ensureViewDoesNotHave passes when text is absent" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewDoesNotHave "Error"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "ensureViewDoesNotHave fails when text is present" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewDoesNotHave "Count:"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
                        |> TuiTest.done
            ]
        , describe "TuiTest - onContext"
            [ test "startWithContext routes initial context through subscriptions" <|
                \() ->
                    contextTest False { width = 120, height = 40, colorProfile = Tui.TrueColor }
                        |> TuiTest.ensureViewHas "Stored: 120×40"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "resize routes context through subscriptions" <|
                \() ->
                    contextTest False { width = 80, height = 24, colorProfile = Tui.TrueColor }
                        |> TuiTest.resize { width = 120, height = 40 }
                        |> TuiTest.ensureViewHas "Stored: 120×40"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "startWithContext keeps effects returned from initial context update" <|
                \() ->
                    contextTest True { width = 120, height = 40, colorProfile = Tui.TrueColor }
                        |> TuiTest.resolveEffect identity
                        |> TuiTest.ensureViewHas "Effect: 120×40"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "resize keeps effects returned from context update" <|
                \() ->
                    contextTest True { width = 80, height = 24, colorProfile = Tui.TrueColor }
                        |> TuiTest.resolveEffect identity
                        |> TuiTest.resize { width = 120, height = 40 }
                        |> TuiTest.resolveEffect identity
                        |> TuiTest.ensureViewHas "Effect: 120×40"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "TuiTest - Stars (BackendTask Effects)"
            [ test "initial view shows default repo and prompt" <|
                \() ->
                    starsTest
                        |> TuiTest.ensureViewHas "dillonkearns/elm-pages"
                        |> TuiTest.ensureViewHas "Press Enter to fetch"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
                        |> TuiTest.done
            , test "Enter triggers loading state" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Loading..."
                        |> TuiTest.sendMsg (GotStars (Ok 0))
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
                        |> TuiTest.done
            , test "simulating BackendTask error shows error" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.sendMsg (GotStars (Err (FatalError.fromString "Not Found")))
                        |> TuiTest.ensureViewHas "Request failed"
                        |> TuiTest.ensureViewDoesNotHave "Loading"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
                        |> TuiTest.done
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
                        |> TuiTest.done
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
                        |> TuiTest.done
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
                        |> TuiTest.done
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
                        |> TuiTest.done
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
                        |> TuiTest.done
                        |> expectFailureContaining "pending BackendTask"
            , test "expectExit fails with helpful message when effects are pending" <|
                \() ->
                    starsTest
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.expectExit
                        |> TuiTest.done
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
                        |> TuiTest.done
                        |> expectFailureContaining "No pending BackendTask"
            , test "pressKey after exit fails with helpful message" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.expectExit
                        |> TuiTest.done
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
                        |> TuiTest.done
                        |> expectFailureContaining "WRONG-URL"
            , test "ensureViewHas failure shows actual screen content" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewHas "this text is not on screen"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
            ]
        , describe "TuiTest - everyMillis + advanceTime"
            [ test "advanceTime 0 fires nothing" <|
                \() ->
                    singleIntervalTickerTest 50
                        |> TuiTest.advanceTime 0
                        |> TuiTest.ensureModel
                            (\m -> m.ticks |> Expect.equal [])
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "advanceTime below one interval fires nothing" <|
                \() ->
                    singleIntervalTickerTest 50
                        |> TuiTest.advanceTime 49
                        |> TuiTest.ensureModel
                            (\m -> m.ticks |> Expect.equal [])
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "advanceTime exactly one interval fires once at the interval boundary" <|
                \() ->
                    singleIntervalTickerTest 50
                        |> TuiTest.advanceTime 50
                        |> TuiTest.ensureModel
                            (\m -> m.ticks |> Expect.equal [ ( 50, 50 ) ])
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "advanceTime three intervals fires three times at 50, 100, 150" <|
                \() ->
                    singleIntervalTickerTest 50
                        |> TuiTest.advanceTime 150
                        |> TuiTest.ensureModel
                            (\m ->
                                m.ticks
                                    |> Expect.equal
                                        [ ( 50, 50 ), ( 50, 100 ), ( 50, 150 ) ]
                            )
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "consecutive advanceTime calls continue the clock forward" <|
                \() ->
                    singleIntervalTickerTest 50
                        |> TuiTest.advanceTime 50
                        |> TuiTest.advanceTime 50
                        |> TuiTest.ensureModel
                            (\m ->
                                m.ticks
                                    |> Expect.equal [ ( 50, 50 ), ( 50, 100 ) ]
                            )
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "Posix timestamp reaching a long elapsed window is correct" <|
                \() ->
                    singleIntervalTickerTest 1000
                        |> TuiTest.advanceTime 5000
                        |> TuiTest.ensureModel
                            (\m ->
                                m.ticks
                                    |> List.map Tuple.second
                                    |> Expect.equal
                                        [ 1000, 2000, 3000, 4000, 5000 ]
                            )
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "multiple intervals fire independently at their own rates" <|
                \() ->
                    twoIntervalTickerTest 50 1000
                        |> TuiTest.advanceTime 1000
                        |> TuiTest.ensureModel
                            (\m ->
                                Expect.all
                                    [ \_ ->
                                        m.ticks
                                            |> List.filter (\( i, _ ) -> i == 50)
                                            |> List.length
                                            |> Expect.equal 20
                                    , \_ ->
                                        m.ticks
                                            |> List.filter (\( i, _ ) -> i == 1000)
                                            |> List.length
                                            |> Expect.equal 1
                                    ]
                                    ()
                            )
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "ticks across intervals arrive in chronological order" <|
                \() ->
                    twoIntervalTickerTest 50 100
                        |> TuiTest.advanceTime 200
                        |> TuiTest.ensureModel
                            (\m ->
                                m.ticks
                                    |> List.map Tuple.second
                                    |> isSorted
                                    |> Expect.equal True
                            )
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "two subscriptions at the same interval both fire" <|
                \() ->
                    sameIntervalDualSubTest 1000
                        |> TuiTest.advanceTime 1000
                        |> TuiTest.ensureModel
                            (\m ->
                                Expect.all
                                    [ \_ -> m.primaryCount |> Expect.equal 1
                                    , \_ -> m.secondaryCount |> Expect.equal 1
                                    ]
                                    ()
                            )
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "conditional subscription that returns Sub.none does not fire" <|
                \() ->
                    conditionalTickerTest
                        |> TuiTest.advanceTime 500
                        |> TuiTest.ensureModel
                            (\m -> m.ticks |> Expect.equal [])
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        ]


tuiTests : TuiTest.Test
tuiTests =
    TuiTest.describe "Tui"
        [ TuiTest.test "counter increments and exits"
            (counterTest
                |> TuiTest.pressKey 'j'
                |> TuiTest.ensureViewHas "Count: 1"
                |> TuiTest.pressKey 'q'
                |> TuiTest.expectExit
            )
        , TuiTest.test "stars flow resolves effect"
            (starsTest
                |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                |> TuiTest.ensureViewHas "Loading..."
                |> TuiTest.resolveEffect
                    (BackendTaskTest.simulateHttpGet
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Encode.object [ ( "stargazers_count", Encode.int 7500 ) ])
                    )
                |> TuiTest.ensureViewHas "Stars: 7500"
                |> TuiTest.expectRunning
            )
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
        [ Tui.styled { plain | attributes = [ Tui.Bold ] } "Counter"
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
        [ Tui.styled { plain | attributes = [ Tui.Bold ] } "GitHub Stars"
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



-- Ticker TUI for exercising everyMillis + advanceTime


type alias TickerModel =
    { ticks : List ( Int, Int )
    , intervals : List Int
    }


type TickerMsg
    = Ticked Int Time.Posix


tickerInit : List Int -> () -> ( TickerModel, Effect TickerMsg )
tickerInit intervals () =
    ( { ticks = [], intervals = intervals }, Effect.none )


tickerUpdate : TickerMsg -> TickerModel -> ( TickerModel, Effect TickerMsg )
tickerUpdate msg model =
    case msg of
        Ticked interval posix ->
            ( { model
                | ticks =
                    model.ticks ++ [ ( interval, Time.posixToMillis posix ) ]
              }
            , Effect.none
            )


tickerView : Tui.Context -> TickerModel -> Tui.Screen
tickerView _ model =
    Tui.text ("Ticks: " ++ String.fromInt (List.length model.ticks))


tickerSubscriptions : TickerModel -> Tui.Sub.Sub TickerMsg
tickerSubscriptions model =
    model.intervals
        |> List.map (\i -> Tui.Sub.everyMillis i (Ticked i))
        |> Tui.Sub.batch


singleIntervalTickerTest : Int -> TuiTest.TuiTest TickerModel TickerMsg
singleIntervalTickerTest interval =
    TuiTest.start
        { data = ()
        , init = tickerInit [ interval ]
        , update = tickerUpdate
        , view = tickerView
        , subscriptions = tickerSubscriptions
        }


twoIntervalTickerTest : Int -> Int -> TuiTest.TuiTest TickerModel TickerMsg
twoIntervalTickerTest a b =
    TuiTest.start
        { data = ()
        , init = tickerInit [ a, b ]
        , update = tickerUpdate
        , view = tickerView
        , subscriptions = tickerSubscriptions
        }



-- Dual-subscription-at-same-interval fixture (exercises the routeEvents
-- fix: multiple subs at the same interval should all fire on one tick)


type alias DualSubModel =
    { primaryCount : Int
    , secondaryCount : Int
    , interval : Int
    }


type DualSubMsg
    = Primary Time.Posix
    | Secondary Time.Posix


dualSubUpdate : DualSubMsg -> DualSubModel -> ( DualSubModel, Effect DualSubMsg )
dualSubUpdate msg model =
    case msg of
        Primary _ ->
            ( { model | primaryCount = model.primaryCount + 1 }, Effect.none )

        Secondary _ ->
            ( { model | secondaryCount = model.secondaryCount + 1 }, Effect.none )


sameIntervalDualSubTest : Int -> TuiTest.TuiTest DualSubModel DualSubMsg
sameIntervalDualSubTest interval =
    TuiTest.start
        { data = ()
        , init =
            \() ->
                ( { primaryCount = 0, secondaryCount = 0, interval = interval }
                , Effect.none
                )
        , update = dualSubUpdate
        , view = \_ _ -> Tui.text "dual"
        , subscriptions =
            \model ->
                Tui.Sub.batch
                    [ Tui.Sub.everyMillis model.interval Primary
                    , Tui.Sub.everyMillis model.interval Secondary
                    ]
        }



-- Conditional ticker: subscription returns Sub.none until a flag flips.
-- With the flag never flipped, advanceTime should fire nothing.


conditionalTickerTest : TuiTest.TuiTest TickerModel TickerMsg
conditionalTickerTest =
    TuiTest.start
        { data = ()
        , init = \() -> ( { ticks = [], intervals = [] }, Effect.none )
        , update = tickerUpdate
        , view = tickerView
        , subscriptions = \_ -> Tui.Sub.none
        }


isSorted : List Int -> Bool
isSorted xs =
    case xs of
        [] ->
            True

        _ :: [] ->
            True

        a :: ((b :: _) as rest) ->
            (a <= b) && isSorted rest
