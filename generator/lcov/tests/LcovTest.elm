module LcovTest exposing (suite)

import Expect
import Lcov exposing (Annotation, AnnotationType(..), ModuleCoverage)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Lcov.generate"
        [ test "single covered declaration spans full line range" <|
            \() ->
                Lcov.generate
                    [ { filePath = "/project/src/MyModule.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "myFunc"
                              , startLine = 5
                              , endLine = 7
                              }
                            ]
                      , hits = [ 0 ]
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/project/src/MyModule.elm"
                            , "FN:5,myFunc"
                            , "FNDA:1,myFunc"
                            , "FNF:1"
                            , "FNH:1"
                            , "DA:5,1"
                            , "DA:6,1"
                            , "DA:7,1"
                            , "LF:3"
                            , "LH:3"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "uncovered declaration shows zero for all lines" <|
            \() ->
                Lcov.generate
                    [ { filePath = "/src/Unused.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "neverCalled"
                              , startLine = 10
                              , endLine = 12
                              }
                            ]
                      , hits = []
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/Unused.elm"
                            , "FN:10,neverCalled"
                            , "FNDA:0,neverCalled"
                            , "FNF:1"
                            , "FNH:0"
                            , "DA:10,0"
                            , "DA:11,0"
                            , "DA:12,0"
                            , "LF:3"
                            , "LH:0"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "multiple hits on same expression" <|
            \() ->
                Lcov.generate
                    [ { filePath = "/src/Repeated.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "helper"
                              , startLine = 3
                              , endLine = 5
                              }
                            ]
                      , hits = [ 0, 0, 0 ]
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/Repeated.elm"
                            , "FN:3,helper"
                            , "FNDA:3,helper"
                            , "FNF:1"
                            , "FNH:1"
                            , "DA:3,3"
                            , "DA:4,3"
                            , "DA:5,3"
                            , "LF:3"
                            , "LH:3"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "branches with overlapping parent declaration" <|
            \() ->
                -- declaration 5-15, branches at 8-9, 11-12, 14-15
                -- branch hit counts override the parent's count on those lines
                Lcov.generate
                    [ { filePath = "/src/Branching.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "classify"
                              , startLine = 5
                              , endLine = 15
                              }
                            , { annotationType = CaseBranch
                              , name = Nothing
                              , startLine = 8
                              , endLine = 9
                              }
                            , { annotationType = CaseBranch
                              , name = Nothing
                              , startLine = 11
                              , endLine = 12
                              }
                            , { annotationType = CaseBranch
                              , name = Nothing
                              , startLine = 14
                              , endLine = 15
                              }
                            ]

                      -- index 0 (declaration) hit once, index 1 (branch 8-9) hit twice,
                      -- index 2 (branch 11-12) never, index 3 (branch 14-15) hit once
                      , hits = [ 0, 1, 1, 3 ]
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/Branching.elm"
                            , "FN:5,classify"
                            , "FNDA:1,classify"
                            , "FNF:1"
                            , "FNH:1"
                            , "BRDA:8,0,0,2"
                            , "BRDA:11,0,1,0"
                            , "BRDA:14,0,2,1"
                            , "BRF:3"
                            , "BRH:2"
                            , "DA:5,1"
                            , "DA:6,1"
                            , "DA:7,1"
                            , "DA:8,2"
                            , "DA:9,2"
                            , "DA:10,1"
                            , "DA:11,0"
                            , "DA:12,0"
                            , "DA:13,1"
                            , "DA:14,1"
                            , "DA:15,1"
                            , "LF:11"
                            , "LH:9"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "let declarations and lambdas expand line ranges" <|
            \() ->
                -- declaration (3-10) hit, let-decl (5-6) hit, lambda (8-9) NOT hit
                -- Lines 8-9 should show 0 because the innermost annotation (lambda) wasn't hit
                Lcov.generate
                    [ { filePath = "/src/Helpers.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "process"
                              , startLine = 3
                              , endLine = 10
                              }
                            , { annotationType = LetDeclaration
                              , name = Nothing
                              , startLine = 5
                              , endLine = 6
                              }
                            , { annotationType = LambdaBody
                              , name = Nothing
                              , startLine = 8
                              , endLine = 9
                              }
                            ]
                      , hits = [ 0, 1 ]
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/Helpers.elm"
                            , "FN:3,process"
                            , "FNDA:1,process"
                            , "FNF:1"
                            , "FNH:1"
                            , "DA:3,1"
                            , "DA:4,1"
                            , "DA:5,1"
                            , "DA:6,1"
                            , "DA:7,1"
                            , "DA:8,0"
                            , "DA:9,0"
                            , "DA:10,1"
                            , "LF:8"
                            , "LH:6"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "multiple modules" <|
            \() ->
                Lcov.generate
                    [ { filePath = "/src/A.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "a"
                              , startLine = 1
                              , endLine = 2
                              }
                            ]
                      , hits = [ 0 ]
                      }
                    , { filePath = "/src/B.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "b"
                              , startLine = 1
                              , endLine = 2
                              }
                            ]
                      , hits = []
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/A.elm"
                            , "FN:1,a"
                            , "FNDA:1,a"
                            , "FNF:1"
                            , "FNH:1"
                            , "DA:1,1"
                            , "DA:2,1"
                            , "LF:2"
                            , "LH:2"
                            , "end_of_record"
                            , ""
                            , "TN:"
                            , "SF:/src/B.elm"
                            , "FN:1,b"
                            , "FNDA:0,b"
                            , "FNF:1"
                            , "FNH:0"
                            , "DA:1,0"
                            , "DA:2,0"
                            , "LF:2"
                            , "LH:0"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "DA covers full line range, not just startLine" <|
            \() ->
                Lcov.generate
                    [ { filePath = "/src/View.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "view"
                              , startLine = 33
                              , endLine = 38
                              }
                            ]
                      , hits = [ 0 ]
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/View.elm"
                            , "FN:33,view"
                            , "FNDA:1,view"
                            , "FNF:1"
                            , "FNH:1"
                            , "DA:33,1"
                            , "DA:34,1"
                            , "DA:35,1"
                            , "DA:36,1"
                            , "DA:37,1"
                            , "DA:38,1"
                            , "LF:6"
                            , "LH:6"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "overlapping line ranges use innermost annotation count" <|
            \() ->
                Lcov.generate
                    [ { filePath = "/src/Overlap.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "foo"
                              , startLine = 5
                              , endLine = 10
                              }
                            , { annotationType = CaseBranch
                              , name = Nothing
                              , startLine = 8
                              , endLine = 9
                              }
                            ]
                      , hits = [ 0, 1, 1, 1 ]
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/Overlap.elm"
                            , "FN:5,foo"
                            , "FNDA:1,foo"
                            , "FNF:1"
                            , "FNH:1"
                            , "BRDA:8,0,0,3"
                            , "BRF:1"
                            , "BRH:1"
                            , "DA:5,1"
                            , "DA:6,1"
                            , "DA:7,1"
                            , "DA:8,3"
                            , "DA:9,3"
                            , "DA:10,1"
                            , "LF:6"
                            , "LH:6"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "pattern lines inherit parent count, only branch bodies show branch count" <|
            \() ->
                -- Mirrors CounterApp: update (23-29) with Increment body at 26,
                -- Decrement body at 29. Pattern lines (25: "Increment ->",
                -- 28: "Decrement ->") are NOT annotated by elm-instrument, so they
                -- inherit the parent declaration's count. Only the body lines show
                -- the actual branch hit count. This is truthful — the pattern IS
                -- evaluated (the case checks it), the body is what's conditionally executed.
                Lcov.generate
                    [ { filePath = "/src/CounterApp.elm"
                      , annotations =
                            [ { annotationType = Declaration
                              , name = Just "update"
                              , startLine = 23
                              , endLine = 29
                              }
                            , { annotationType = CaseBranch
                              , name = Nothing
                              , startLine = 26
                              , endLine = 26
                              }
                            , { annotationType = CaseBranch
                              , name = Nothing
                              , startLine = 29
                              , endLine = 29
                              }
                            ]
                      , hits = [ 0, 1 ]
                      }
                    ]
                    |> Expect.equal
                        (String.join "\n"
                            [ "TN:"
                            , "SF:/src/CounterApp.elm"
                            , "FN:23,update"
                            , "FNDA:1,update"
                            , "FNF:1"
                            , "FNH:1"
                            , "BRDA:26,0,0,1"
                            , "BRDA:29,0,1,0"
                            , "BRF:2"
                            , "BRH:1"
                            , "DA:23,1"
                            , "DA:24,1"
                            , "DA:25,1"
                            , "DA:26,1"
                            , "DA:27,1"
                            , "DA:28,1"
                            , "DA:29,0"
                            , "LF:7"
                            , "LH:6"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "empty module list" <|
            \() ->
                Lcov.generate []
                    |> Expect.equal ""
        ]
