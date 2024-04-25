module Pages.Script exposing
    ( Script
    , withCliOptions, withoutCliOptions
    , writeFile
    , command, exec
    , log, sleep, doThen, which, expectWhich, question
    , Error(..)
    )

{-| An elm-pages Script is a way to execute an `elm-pages` `BackendTask`.

Read more about using the `elm-pages` CLI to run (or bundle) scripts, plus a brief tutorial, at <https://elm-pages.com/docs/elm-pages-scripts>.

@docs Script


## Defining Scripts

@docs withCliOptions, withoutCliOptions


## File System Utilities

@docs writeFile


## Shell Commands

@docs command, exec


## Utilities

@docs log, sleep, doThen, which, expectWhich, question


## Errors

@docs Error

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import BackendTask.Stream as Stream exposing (defaultCommandOptions)
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.Script


{-| The type for your `run` function that can be executed by `elm-pages run`.
-}
type alias Script =
    Pages.Internal.Script.Script


{-| The recoverable error type for file writes. You can use `BackendTask.allowFatal` if you want to allow the program to crash
with an error message if a file write is unsuccessful.
-}
type Error
    = --TODO make more descriptive
      FileWriteError


{-| Write a file to the file system.

File paths are relative to the root of your `elm-pages` project (next to the `elm.json` file and `src/` directory), or you can pass in absolute paths beginning with a `/`.

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script

    run =
        Script.withoutCliOptions
            (Script.writeFile
                { path = "hello.json"
                , body = """{ "message": "Hello, World!" }"""
                }
                |> BackendTask.allowFatal
            )

-}
writeFile : { path : String, body : String } -> BackendTask { fatal : FatalError, recoverable : Error } ()
writeFile { path, body } =
    BackendTask.Internal.Request.request
        { name = "write-file"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "path", Encode.string path )
                    , ( "body", Encode.string body )
                    ]
                )
        , expect =
            -- TODO decode possible error details here
            BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Log to stdout.

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script

    run =
        Script.withoutCliOptions
            (Script.log "Hello!"
                |> BackendTask.allowFatal
            )

-}
log : String -> BackendTask error ()
log message =
    BackendTask.Internal.Request.request
        { name = "log"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "message", Encode.string message )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Define a simple Script (no CLI Options).

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script

    run =
        Script.withoutCliOptions
            (Script.log "Hello!"
                |> BackendTask.allowFatal
            )

-}
withoutCliOptions : BackendTask FatalError () -> Script
withoutCliOptions execute =
    Pages.Internal.Script.Script
        (\_ ->
            Program.config
                |> Program.add
                    (OptionsParser.build ())
                |> Program.mapConfig
                    (\() ->
                        execute
                    )
        )


{-| Same as [`withoutCliOptions`](#withoutCliOptions), but allows you to define a CLI Options Parser so the user can
pass in additional options for the script.

Uses <https://package.elm-lang.org/packages/dillonkearns/elm-cli-options-parser/latest/>.

Read more at <https://elm-pages.com/docs/elm-pages-scripts/#adding-command-line-options>.

-}
withCliOptions : Program.Config cliOptions -> (cliOptions -> BackendTask FatalError ()) -> Script
withCliOptions config execute =
    Pages.Internal.Script.Script
        (\_ ->
            config
                |> Program.mapConfig execute
        )


{-| Sleep for a number of milliseconds.

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script

    run =
        Script.withoutCliOptions
            (Script.log "Hello..."
                |> Script.doThen
                    (Script.sleep 1000)
                |> Script.doThen
                    (Script.log "World!")
            )

-}
sleep : Int -> BackendTask error ()
sleep int =
    BackendTask.Internal.Request.request
        { name = "sleep"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "milliseconds", Encode.int int )
                    ]
                )
        , expect =
            BackendTask.Http.expectJson (Decode.null ())
        }


{-| Run a command with no output, then run another command.

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script

    run =
        Script.withoutCliOptions
            (Script.log "Hello!"
                |> Script.doThen
                    (Script.log "World!")
            )

-}
doThen : BackendTask error value -> BackendTask error () -> BackendTask error value
doThen task1 task2 =
    task2
        |> BackendTask.andThen (\() -> task1)


{-| Same as [`expectWhich`](#expectWhich), but returns `Nothing` if the command is not found instead of failing with a [`FatalError`](FatalError).
-}
which : String -> BackendTask error (Maybe String)
which command_ =
    BackendTask.Internal.Request.request
        { body = BackendTask.Http.jsonBody (Encode.string command_)
        , expect = BackendTask.Http.expectJson (Decode.nullable Decode.string)
        , name = "which"
        }


{-| Check if a command is available on the system. If it is, return the full path to the command, otherwise fail with a [`FatalError`](FatalError).

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script

    run : Script
    run =
        Script.withoutCliOptions
            (Script.expectWhich "elm-review"
                |> BackendTask.andThen
                    (\path ->
                        Script.log ("The path to `elm-review` is: " ++ path)
                    )
            )

If you run it with a command that is not available, you will see an error like this:

    Script.expectWhich "hype-script"

```shell
-- COMMAND NOT FOUND ---------------
I expected to find `hype-script`, but it was not on your PATH. Make sure it is installed and included in your PATH.
```

-}
expectWhich : String -> BackendTask FatalError String
expectWhich command_ =
    which command_
        |> BackendTask.andThen
            (\maybePath ->
                case maybePath of
                    Just path ->
                        BackendTask.succeed path

                    Nothing ->
                        BackendTask.fail
                            (FatalError.build
                                { title = "Command not found"
                                , body = "I expected to find `" ++ command_ ++ "`, but it was not on your PATH. Make sure it is installed and included in your PATH."
                                }
                            )
            )


{-|

    module QuestionDemo exposing (run)

    import BackendTask

    run : Script
    run =
        Script.withoutCliOptions
            (Script.question "What is your name? "
                |> BackendTask.andThen
                    (\name ->
                        Script.log ("Hello, " ++ name ++ "!")
                    )
            )

-}
question : String -> BackendTask error String
question prompt =
    BackendTask.Internal.Request.request
        { body =
            BackendTask.Http.jsonBody
                (Encode.object [ ( "prompt", Encode.string prompt ) ])
        , expect = BackendTask.Http.expectJson Decode.string
        , name = "question"
        }


{-| Like [`command`](#command), but prints stderr and stdout to the console as the command runs instead of capturing them.

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Script.exec "ls" [])

-}
exec : String -> List String -> BackendTask FatalError ()
exec command_ args_ =
    Stream.command command_ args_
        |> Stream.run


{-| Run a single command and return stderr and stdout combined as a single String.

If you want to do more advanced things like piping together multiple commands in a pipeline, or piping in a file to a command, etc., see the [`Stream`](BackendTask-Stream) module.

    module MyScript exposing (run)

    import BackendTask
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Script.command "ls" []
                |> BackendTask.andThen
                    (\files ->
                        Script.log ("Files: " ++ files)
                    )
            )

-}
command : String -> List String -> BackendTask FatalError String
command command_ args_ =
    Stream.commandWithOptions
        (defaultCommandOptions |> Stream.withOutput Stream.MergeStderrAndStdout)
        command_
        args_
        |> Stream.read
        |> BackendTask.map .body
        |> BackendTask.allowFatal
