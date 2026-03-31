module LcovTest exposing (suite)

import Expect
import Lcov exposing (Annotation, AnnotationType(..), ModuleCoverage)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Lcov.generate"
        [ test "single covered declaration" <|
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
                            , "LF:1"
                            , "LH:1"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "uncovered declaration shows zero count" <|
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
                            , "LF:1"
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
                            , "LF:1"
                            , "LH:1"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "mixed annotation types including branches" <|
            \() ->
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

                      -- index 0 (declaration) hit, index 1 (first branch) hit twice, index 2 (second branch) never hit, index 3 (third branch) hit once
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
                            , "DA:8,2"
                            , "DA:11,0"
                            , "DA:14,1"
                            , "LF:4"
                            , "LH:3"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "let declarations and lambdas are DA lines but not FN" <|
            \() ->
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
                            , "DA:5,1"
                            , "DA:8,0"
                            , "LF:3"
                            , "LH:2"
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
                            , "LF:1"
                            , "LH:1"
                            , "end_of_record"
                            , ""
                            , "TN:"
                            , "SF:/src/B.elm"
                            , "FN:1,b"
                            , "FNDA:0,b"
                            , "FNF:1"
                            , "FNH:0"
                            , "DA:1,0"
                            , "LF:1"
                            , "LH:0"
                            , "end_of_record"
                            , ""
                            ]
                        )
        , test "empty module list" <|
            \() ->
                Lcov.generate []
                    |> Expect.equal ""
        ]
