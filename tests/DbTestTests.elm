module DbTestTests exposing (all)

import BackendTask
import BackendTask.Http
import Expect
import FakeDb
import Json.Decode
import Json.Encode
import Pages.Script as Script
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest


all : Test
all =
    describe "DB virtual layer"
        [ describe "withDb"
            [ test "script that reads DB gets the seeded value" <|
                \() ->
                    FakeDb.get
                        |> BackendTask.andThen
                            (\db ->
                                Script.log ("counter=" ++ String.fromInt db.counter)
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDbSetTo { counter = 42, name = "test" } FakeDb.testConfig
                            )
                        |> BackendTaskTest.ensureStdout [ "counter=42" ]
                        |> BackendTaskTest.expectSuccess
            , test "script that updates DB persists the change" <|
                \() ->
                    FakeDb.update (\db -> { db | counter = db.counter + 1 })
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDbSetTo { counter = 10, name = "test" } FakeDb.testConfig
                            )
                        |> BackendTaskTest.expectDb FakeDb.testConfig
                            (\db -> Expect.equal 11 db.counter)
            , test "two consecutive updates accumulate" <|
                \() ->
                    FakeDb.update (\db -> { db | counter = db.counter + 1 })
                        |> BackendTask.andThen
                            (\() ->
                                FakeDb.update (\db -> { db | counter = db.counter * 10 })
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDbSetTo { counter = 5, name = "" } FakeDb.testConfig
                            )
                        |> BackendTaskTest.expectDb FakeDb.testConfig
                            (\db -> Expect.equal 60 db.counter)
            , test "withDb uses seed from testConfig" <|
                \() ->
                    FakeDb.update (\db -> { db | counter = db.counter + 1 })
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDb FakeDb.testConfig
                            )
                        |> BackendTaskTest.expectDb FakeDb.testConfig
                            (\db -> Expect.equal 1 db.counter)
            , test "returned values can be asserted after DB setup" <|
                \() ->
                    FakeDb.update (\db -> { db | counter = db.counter + 1 })
                        |> BackendTask.andThen (\() -> FakeDb.get)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDbSetTo { counter = 10, name = "test" } FakeDb.testConfig
                            )
                        |> BackendTaskTest.expectSuccessWith
                            (\db -> Expect.equal 11 db.counter)
            , test "DB + HTTP simulation combined" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/count"
                        (Json.Decode.field "value" Json.Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\count ->
                                FakeDb.update (\db -> { db | counter = db.counter + count })
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDbSetTo { counter = 0, name = "" } FakeDb.testConfig
                            )
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.example.com/count"
                            (Json.Encode.object [ ( "value", Json.Encode.int 7 ) ])
                        |> BackendTaskTest.expectDb FakeDb.testConfig
                            (\db -> Expect.equal 7 db.counter)
            , test "DB + file write combined" <|
                \() ->
                    FakeDb.get
                        |> BackendTask.andThen
                            (\db ->
                                Script.writeFile
                                    { path = "output.txt"
                                    , body = "counter=" ++ String.fromInt db.counter
                                    }
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDbSetTo { counter = 99, name = "" } FakeDb.testConfig
                            )
                        |> BackendTaskTest.ensureFile "output.txt" "counter=99"
                        |> BackendTaskTest.expectSuccess
            , test "string fields round-trip through DB" <|
                \() ->
                    FakeDb.update (\db -> { db | name = "hello world" })
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withDbSetTo { counter = 0, name = "" } FakeDb.testConfig
                            )
                        |> BackendTaskTest.expectDb FakeDb.testConfig
                            (\db -> Expect.equal "hello world" db.name)
            ]
        , describe "error messages"
            [ test "DB ops without setup produce helpful error" <|
                \() ->
                    FakeDb.get
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.all
                                    [ \m -> Expect.equal True (String.contains "Pages.Db" m)
                                    , \m -> Expect.equal True (String.contains "withDb" m)
                                    ]
                                    msg
                            )
            ]
        ]
