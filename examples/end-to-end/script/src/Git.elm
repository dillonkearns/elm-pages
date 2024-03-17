module Git exposing (Client, currentBranch, try, withClient)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Script as Script


type Client
    = Client String


withClient : String -> BackendTask FatalError Client
withClient directory =
    Script.expectWhich "git"
        |> BackendTask.map (\_ -> Client directory)


{-|

    run : Script
    run =
        Script.withoutCliOptions
            (Git.try Git.branch
                |> BackendTask.andThen Script.log
            )

-}
try : (Client -> BackendTask FatalError String) -> BackendTask FatalError String
try function =
    withClient "./"
        |> BackendTask.andThen function


currentBranch : Client -> BackendTask error String
currentBranch client =
    gitCmd client "rev-parse --abbrev-ref HEAD"
        |> BackendTask.onError (\_ -> BackendTask.succeed "master")


gitCmd : Client -> String -> BackendTask error String
gitCmd (Client clientPath) command =
    --Script.shell ("(cd " ++ clientPath ++ " && git " ++ command ++ ")")
    --    |> BackendTask.map .output
    Script.shell [ ( "git", [ command ] ) ]
        |> BackendTask.map .output
        |> BackendTask.onError (\_ -> BackendTask.succeed "")
