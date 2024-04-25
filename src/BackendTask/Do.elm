module BackendTask.Do exposing
    ( do
    , allowFatal
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
@docs allowFatal


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


{-| A do-style helper for [`Script.log`](Pages-Script#log).

    example : BackendTask FatalError ()
    example =
        log "Starting script..." <|
            \() ->
                -- ...
                log "Done!" <|
                    \() ->
                        noop

-}
log : String -> (() -> BackendTask error b) -> BackendTask error b
log string then_ =
    do (Script.log string) then_


{-| Use any `BackendTask` into a continuation-style task.

    example : BackendTask FatalError ()
    example =
        do
            (Script.question "What is your name? ")
        <|
            \name ->
                \() ->
                    Script.log ("Hello " ++ name ++ "!")

-}
do : BackendTask error a -> (a -> BackendTask error b) -> BackendTask error b
do fn requestInfo =
    BackendTask.andThen requestInfo fn


{-| A `BackendTask` that does nothing. Defined as `BackendTask.succeed ()`.

It's a useful shorthand for when you want to end a continuation chain.

    example : BackendTask FatalError ()
    example =
        exec "ls" [ "-l" ] <|
            \() ->
                log "Hello, world!" <|
                    \() ->
                        noop

-}
noop : BackendTask error ()
noop =
    BackendTask.succeed ()


{-| Same as [`do`](#do), but with a shorthand to call `BackendTask.allowFatal` on it.

    import BackendTask exposing (BackendTask)
    import FatalError exposing (FatalError)
    import BackendTask.File as BackendTask.File
    import BackendTask.Do exposing (allowFatal, do)

    example : BackendTask FatalError ()
    example =
        do (BackendTask.File.rawFile "post-1.md" |> BackendTask.allowFatal) <|
            \post1 ->
                allowFatal (BackendTask.File.rawFile "post-2.md") <|
                    \post2 ->
                        Script.log (post1 ++ "\n\n" ++ post2)

-}
allowFatal : BackendTask { error | fatal : FatalError } data -> (data -> BackendTask FatalError b) -> BackendTask FatalError b
allowFatal =
    do << BackendTask.allowFatal


{-| A continuation-style helper for [`Glob.fromString`](BackendTask-Glob#fromString).

In a shell script, you can think of this as a stand-in for globbing files directly within a command. The [`BackendTask.Stream.command`](BackendTask-Stream#command)
which lets you run shell commands sanitizes and escapes all arguments passed, and does not do glob expansion, so this is helpful for translating
a shell script to Elm.

This example passes a list of matching file paths along to an `rm -f` command.

    example : BackendTask FatalError ()
    example =
        glob "src/**/*.elm" <|
            \elmFiles ->
                log ("Going to delete " ++ String.fromInt (List.length elmFiles) ++ " Elm files") <|
                    \() ->
                        exec "rm" ("-f" :: elmFiles) <|
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


{-| A do-style helper for [`BackendTask.failIf`](BackendTask#failIf).
-}
failIf : Bool -> FatalError -> (() -> BackendTask FatalError b) -> BackendTask FatalError b
failIf condition error =
    do <| BackendTask.failIf condition error


{-| A do-style helper for [`Script.exec`](Pages-Script#exec).
-}
exec : String -> List String -> (() -> BackendTask FatalError b) -> BackendTask FatalError b
exec command_ args_ =
    do <| Script.exec command_ args_


{-| A do-style helper for [`Script.command`](Pages-Script#command).
-}
command : String -> List String -> (String -> BackendTask FatalError b) -> BackendTask FatalError b
command command_ args_ function =
    Script.command command_ args_
        |> BackendTask.andThen function


{-| A do-style helper for [`Env.expect`](BackendTask-Env#expect).

    example : BackendTask FatalError ()
    example =
        env "API_KEY" <|
            \apiKey ->
                allowFatal (apiRequest apiKey) <|
                    \() ->
                        noop

-}
env : String -> (String -> BackendTask FatalError b) -> BackendTask FatalError b
env name then_ =
    do (Env.expect name |> BackendTask.allowFatal) <| then_
