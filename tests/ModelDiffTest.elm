module ModelDiffTest exposing (suite)

{-| Pin the model-diff behavior used by the visual test viewer's
Model panel (pass 11). Each test exercises one of the diff cases:
Mutated leaf, Added record key, Restructured (variant tag /
list-length / record-shape change).
-}

import Dict
import Expect
import Test exposing (Test, describe, test)
import Test.PagesProgram.DebugParser as DP


parseOk : String -> DP.ElmValue
parseOk s =
    case DP.parse s of
        Ok v ->
            v

        Err _ ->
            Debug.todo ("Test setup failed to parse: " ++ s)


suite : Test
suite =
    describe "DebugParser.diff"
        [ test "leaf mutation marks the path" <|
            \() ->
                DP.diff (parseOk "{ x = 1 }") (parseOk "{ x = 2 }")
                    |> Dict.toList
                    |> Expect.equal [ ( "root.x", DP.Mutated ) ]
        , test "added record key" <|
            \() ->
                DP.diff (parseOk "{ x = 1 }") (parseOk "{ x = 1, y = 2 }")
                    |> Dict.toList
                    |> Expect.equal [ ( "root.y", DP.Added ) ]
        , test "variant tag swap is restructured at the variant path" <|
            \() ->
                DP.diff (parseOk "{ nav = Loading }") (parseOk "{ nav = Loaded }")
                    |> Dict.toList
                    |> Expect.equal [ ( "root.nav", DP.Restructured ) ]
        , test "list length change is restructured (no descendants marked)" <|
            \() ->
                DP.diff (parseOk "{ items = [1, 2] }") (parseOk "{ items = [1, 2, 3] }")
                    |> Dict.toList
                    |> Expect.equal [ ( "root.items", DP.Restructured ) ]
        , test "no change → empty diff" <|
            \() ->
                DP.diff (parseOk "{ x = 1 }") (parseOk "{ x = 1 }")
                    |> Dict.toList
                    |> Expect.equal []
        , test "nested change finds the deepest path" <|
            \() ->
                DP.diff
                    (parseOk "{ app = { data = { count = 1 } } }")
                    (parseOk "{ app = { data = { count = 2 } } }")
                    |> Dict.toList
                    |> Expect.equal [ ( "root.app.data.count", DP.Mutated ) ]
        , test "list element leaf change marks the indexed path" <|
            \() ->
                DP.diff
                    (parseOk "{ items = [{ done = False }, { done = True }] }")
                    (parseOk "{ items = [{ done = True }, { done = True }] }")
                    |> Dict.toList
                    |> Expect.equal [ ( "root.items.0.done", DP.Mutated ) ]
        ]
