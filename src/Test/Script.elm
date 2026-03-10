module Test.Script exposing
    ( fromScript, fromScriptWith
    , simulateCommand
    , simulateQuestion, simulateReadKey
    )

{-| Test full `Script` values including CLI option parsing.


## Building

@docs fromScript, fromScriptWith


## Simulating

@docs simulateCommand


## Interactive Input

@docs simulateQuestion, simulateReadKey

-}

import Pages.Script exposing (Script)
import Test.BackendTask.Internal as Internal exposing (BackendTaskTest, TestSetup)


{-| Start a test from a [`Script`](Pages-Script#Script) with simulated CLI arguments.
This tests the full script including CLI option parsing.

    import Test.Script as ScriptTest

    myScript
        |> ScriptTest.fromScript [ "--name", "Dillon" ]
        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
        |> BackendTaskTest.expectSuccess

-}
fromScript : List String -> Script -> BackendTaskTest ()
fromScript =
    Internal.fromScript


{-| Like [`fromScript`](#fromScript) but with a configured
[`TestSetup`](Test-BackendTask-Internal#TestSetup).

    import Test.BackendTask as BackendTaskTest
    import Test.Script as ScriptTest

    myScript
        |> ScriptTest.fromScriptWith
            (BackendTaskTest.init
                |> BackendTaskTest.withFile "config.json" "{}"
            )
            []
        |> BackendTaskTest.expectSuccess

-}
fromScriptWith : TestSetup -> List String -> Script -> BackendTaskTest ()
fromScriptWith =
    Internal.fromScriptWith


{-| Simulate a pending `Stream.command` / `Script.command` / `Script.exec` call.
The framework handles simulatable parts around the command. You provide the
command name and its output.

    import Test.Script as ScriptTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> ScriptTest.simulateCommand "grep" "matched line\n"
        |> BackendTaskTest.expectSuccess

-}
simulateCommand : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCommand commandName commandOutput =
    Internal.simulateCommand commandName commandOutput


{-| Simulate a pending `Script.question` call. The prompt must match the prompt
text passed to `Script.question`.

    import Test.Script as ScriptTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> ScriptTest.simulateQuestion "What is your name? " "Dillon"
        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
        |> BackendTaskTest.expectSuccess

-}
simulateQuestion : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateQuestion prompt answer =
    Internal.simulateQuestion prompt answer


{-| Simulate a pending `Script.readKey` call resolving with the given key.

    import Test.Script as ScriptTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> ScriptTest.simulateReadKey "y"
        |> BackendTaskTest.ensureStdout [ "confirmed" ]
        |> BackendTaskTest.expectSuccess

-}
simulateReadKey : String -> BackendTaskTest a -> BackendTaskTest a
simulateReadKey key =
    Internal.simulateReadKey key
