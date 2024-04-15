module BackendTask.Do exposing
    ( do
    , noop
    , exec, command
    , glob, log, env
    , each, failIf
    )

{-|


## **This is an optional and experimental module.** It is for doing a continuation style with your [`BackendTask`s](BackendTask).

Note that in order for this style to be usable, you'll need to use a special formatting script that allows you to use
continuation style syntax without indenting each level in the continuation.


## Custom Formatting Script

It is a bit advanced and cumbersome, so beware before committing to this style. That said, here is a script you can use to
apply continuation-style formatting to your Elm code:

<https://gist.github.com/xarvh/1b65cb00e7240f1ccfa0bdbf30f97c62>

You can see more discussion of continuation style in Elm in this Discourse post: <https://discourse.elm-lang.org/t/experimental-json-decoding-api/2121>.

@docs do


## Defining Your Own Continuation Utilities

`do` is also helpful for building your own continuation-style utilities. For example, here is how [`glob`](#glob) is defined:

    glob : String -> (List String -> BackendTask FatalError a) -> BackendTask FatalError a
    glob pattern =
        do <| Glob.fromString pattern

To define helpers that have no resulting value, it is still useful to have an argument of `()` to allow the code formatter to
recognize it as a continuation chain.

    sh :
        String
        -> List String
        -> (() -> BackendTask FatalError b)
        -> BackendTask FatalError b
    sh command args =
        do <| Shell.sh command args

@docs noop


## Shell Commands

@docs exec, command


## Common Utilities

@docs glob, log, env

@docs each, failIf

-}

import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import BackendTask.Glob as Glob
import FatalError exposing (FatalError)
import Pages.Script as Script


{-| -}
log : String -> (() -> BackendTask error b) -> BackendTask error b
log string then_ =
    do (Script.log string) then_


{-| Use any `BackendTask` into a continuation-style task.
-}
do : BackendTask error a -> (a -> BackendTask error b) -> BackendTask error b
do fn requestInfo =
    BackendTask.andThen requestInfo fn


{-| -}
noop : BackendTask error ()
noop =
    BackendTask.succeed ()


{-| A continuation-style helper for [`Glob.fromString`](BackendTask-Glob#fromString).

In a shell script, you can think of this as a stand-in for globbing files directly within a command. The [`BackendTask.Stream.command`](BackendTask-Stream#command)
which lets you run shell commands sanitizes and escapes all arguments passed, and does not do glob expansion, so this is helpful for translating
a shell script to Elm.

This example passes a list of matching file paths along to an `rm -f` command.

    example : BackendTask FatalError ()
    example =
        glob "src/**/*.elm" <|
            \elmFiles ->
                log ("You have " ++ String.fromInt (List.length elmFiles) ++ " Elm files") <|
                    \() ->
                        noop

-}
glob : String -> (List String -> BackendTask FatalError a) -> BackendTask FatalError a
glob pattern =
    do <| Glob.fromString pattern


{-|

    checkCompilationInDir : String -> BackendTask FatalError ()
    checkCompilationInDir dir =
        glob (dir ++ "/**/*.elm") <|
            \elmFiles ->
                each elmFiles
                    (\elmFile ->
                        Shell.sh "elm" [ "make", elmFile, "--output", "/dev/null" ]
                            |> BackendTask.quiet
                    )
                <|
                    \_ ->
                        noop

-}
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
exec : String -> List String -> (() -> BackendTask FatalError b) -> BackendTask FatalError b
exec command_ args_ =
    do <| Script.exec command_ args_


{-| -}
command : String -> List String -> (String -> BackendTask FatalError b) -> BackendTask FatalError b
command command_ args_ function =
    Script.command command_ args_
        |> BackendTask.andThen function


{-| -}
env : String -> (String -> BackendTask FatalError b) -> BackendTask FatalError b
env name then_ =
    do (Env.expect name |> BackendTask.allowFatal) <| then_
