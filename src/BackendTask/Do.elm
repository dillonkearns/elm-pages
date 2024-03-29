module BackendTask.Do exposing
    ( do, each, failIf, glob, log, noop, env
    , sh, exec
    )

{-|


## **This is an optional and experimental module.** It is for doing a continuation style with your [`BackendTask`s](BackendTask).

Note that in order for this style to be usable, you'll need to use a special formatting script that allows you to use
continuation style syntax without indenting each level in the continuation.

@docs do, each, failIf, glob, log, noop, env

@docs sh, exec

-}

import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import BackendTask.Glob as Glob
import BackendTask.Shell as Shell
import FatalError exposing (FatalError)
import Pages.Script as Script


{-| -}
log : String -> (() -> BackendTask error b) -> BackendTask error b
log string then_ =
    do (Script.log string) then_


{-| -}
do : BackendTask error a -> (a -> BackendTask error b) -> BackendTask error b
do fn requestInfo =
    BackendTask.andThen requestInfo fn


{-| -}
noop : BackendTask error ()
noop =
    BackendTask.succeed ()


{-| -}
glob : String -> (List String -> BackendTask FatalError a) -> BackendTask FatalError a
glob pattern then_ =
    do (Glob.fromString pattern) then_


{-| -}
each : List a -> (a -> BackendTask error b) -> (List b -> BackendTask error c) -> BackendTask error c
each list fn then_ =
    do
        (list
            |> List.map fn
            |> BackendTask.sequence
        )
    <|
        then_


{-| -}
failIf : Bool -> FatalError -> (() -> BackendTask FatalError b) -> BackendTask FatalError b
failIf condition error =
    do <| BackendTask.failIf condition error


{-| -}
sh : String -> List String -> (() -> BackendTask FatalError b) -> BackendTask FatalError b
sh command_ args_ =
    do <| Shell.sh command_ args_


{-| -}
exec : Shell.Command stdout -> (() -> BackendTask FatalError b) -> BackendTask FatalError b
exec command function =
    command
        |> Shell.exec
        |> BackendTask.andThen function


{-| -}
env : String -> (String -> BackendTask FatalError b) -> BackendTask FatalError b
env name then_ =
    do (Env.expect name |> BackendTask.allowFatal) <| then_
