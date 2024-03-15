module Pages.Script exposing
    ( Script
    , withCliOptions, withoutCliOptions
    , writeFile
    , sh, shell
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

@docs sh, shell


## Utilities

@docs log, sleep, doThen, which, expectWhich, question


## Errors

@docs Error

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
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


{-| -}
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


{-| -}
doThen : BackendTask error value -> BackendTask error () -> BackendTask error value
doThen task1 task2 =
    task2
        |> BackendTask.andThen (\() -> task1)


{-| -}
which : String -> BackendTask error (Maybe String)
which command =
    BackendTask.Internal.Request.request
        { body = BackendTask.Http.jsonBody (Encode.string command)
        , expect = BackendTask.Http.expectJson (Decode.nullable Decode.string)
        , name = "which"
        }


{-| -}
expectWhich : String -> BackendTask FatalError String
expectWhich command =
    which command
        |> BackendTask.andThen
            (\maybePath ->
                case maybePath of
                    Just path ->
                        BackendTask.succeed path

                    Nothing ->
                        BackendTask.fail
                            (FatalError.build
                                { title = "Command not found"
                                , body = "I expected to find `" ++ command ++ "`, but it was not on your PATH. Make sure it is installed and included in your PATH."
                                }
                            )
            )


{-| -}
question : String -> BackendTask error String
question prompt =
    BackendTask.Internal.Request.request
        { body =
            BackendTask.Http.jsonBody
                (Encode.object [ ( "prompt", Encode.string prompt ) ])
        , expect = BackendTask.Http.expectJson Decode.string
        , name = "question"
        }


{-| -}
sh : String -> BackendTask FatalError String
sh command =
    shell command |> BackendTask.map (.output >> removeTrailingNewline) |> BackendTask.allowFatal


removeTrailingNewline : String -> String
removeTrailingNewline str =
    if String.endsWith "\n" str then
        String.dropRight 1 str

    else
        str


{-| -}
shell :
    String
    ->
        BackendTask
            { fatal : FatalError
            , recoverable :
                { output : String
                , stderr : String
                , stdout : String
                , statusCode : Int
                }
            }
            { output : String
            , stderr : String
            , stdout : String
            }
shell command =
    BackendTask.Internal.Request.request
        { name = "shell"
        , body = BackendTask.Http.jsonBody (Encode.string command)
        , expect = BackendTask.Http.expectJson commandDecoder
        }
        |> BackendTask.andThen
            (\rawOutput ->
                if rawOutput.exitCode == 0 then
                    BackendTask.succeed
                        { output = rawOutput.output
                        , stderr = rawOutput.stderr
                        , stdout = rawOutput.stdout
                        }

                else
                    FatalError.recoverable { title = "", body = "" }
                        { output = rawOutput.output
                        , stderr = rawOutput.stderr
                        , stdout = rawOutput.stdout
                        , statusCode = rawOutput.exitCode
                        }
                        |> BackendTask.fail
            )


type alias RawOutput =
    { exitCode : Int
    , output : String
    , stderr : String
    , stdout : String
    }


commandDecoder : Decode.Decoder RawOutput
commandDecoder =
    Decode.map4 RawOutput
        (Decode.field "errorCode" Decode.int)
        (Decode.field "output" Decode.string)
        (Decode.field "stderrOutput" Decode.string)
        (Decode.field "stdoutOutput" Decode.string)
