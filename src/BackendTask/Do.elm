module BackendTask.Do exposing (do, each, failIf, glob, log, noop)

import BackendTask exposing (BackendTask)
import BackendTask.Glob as Glob
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



--sh : String -> List String -> (() -> BackendTask FatalError b) -> BackendTask FatalError b
--sh command_ args_ =
--    do <| Shell.sh command_ args_
