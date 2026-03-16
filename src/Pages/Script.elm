module Pages.Script exposing
    ( Script
    , withCliOptions, withoutCliOptions, withSchema, metadata, withDatabasePath
    , tui, tuiWithCliOptions
    , writeFile, removeFile, copyFile, move
    , makeDirectory, removeDirectory, makeTempDirectory
    , command, exec
    , log, sleep, doThen, which, expectWhich, question, readKey, readKeyWithDefault
    , Error(..)
    )

{-| An elm-pages Script is a way to execute an `elm-pages` `BackendTask`.

Read more about using the `elm-pages` CLI to run (or bundle) scripts, plus a brief tutorial, at <https://elm-pages.com/docs/elm-pages-scripts>.

@docs Script


## Defining Scripts

@docs withCliOptions, withoutCliOptions, withSchema, metadata, withDatabasePath


## TUI Scripts

@docs tui, tuiWithCliOptions


## File System Utilities

@docs writeFile, removeFile, copyFile, move

@docs makeDirectory, removeDirectory, makeTempDirectory


## Shell Commands

@docs command, exec


## Utilities

@docs log, sleep, doThen, which, expectWhich, question, readKey, readKeyWithDefault


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
import Tui
import Tui.Effect
import Tui.Internal
import Tui.Sub
import TsJson.Encode
import TsJson.Type


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
        { toConfig =
            \_ ->
                Program.config
                    |> Program.add
                        (OptionsParser.build ())
                    |> Program.mapConfig
                        (\() ->
                            execute
                        )
        , metadata = Nothing
        }


{-| Same as [`withoutCliOptions`](#withoutCliOptions), but allows you to define a CLI Options Parser so the user can
pass in additional options for the script.

Uses <https://package.elm-lang.org/packages/dillonkearns/elm-cli-options-parser/latest/>.

Read more at <https://elm-pages.com/docs/elm-pages-scripts/#adding-command-line-options>.

-}
withCliOptions : Program.Config cliOptions -> (cliOptions -> BackendTask FatalError ()) -> Script
withCliOptions config execute =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                config
                    |> Program.mapConfig execute
        , metadata = Nothing
        }


{-| Like [`withCliOptions`](#withCliOptions), but with a typed output schema.

The return value of your `run` function is automatically JSON-encoded and
printed to stdout using the provided encoder. Running with `--introspect-cli`
short-circuits execution and prints metadata including the script's
`inputSchema` and output JSON Schema instead, so that tools and LLM agents
can discover how to call the script and what it returns without running it.

The schema is derived from the same `Encoder` that does the actual encoding,
so it can never drift out of sync with the real output.

`description` is a short summary of what the script does. It appears in
`--introspect-cli` output so that tools can decide whether to call it. The
`help` field in the output is the usage synopsis from `--help` (without
ANSI colors). Scripts defined with `withSchema` are also automatically
included in `elm-pages introspect`; you do not need to expose any extra
top-level values for that to work. To invoke a script with JSON input
directly, pass the JSON object as a single shell argument.

Example: a script that checks whether a URL is reachable.

    -- file: script/src/CheckStatus.elm
    run : Script
    run =
        Script.withSchema
            { description =
                "Check whether a URL is reachable"
            , cliOptions =
                Program.config
                    |> Program.add
                        (OptionsParser.build identity
                            |> OptionsParser.with
                                (Option.requiredKeywordArg "url")
                        )
            , encoder =
                TsEncode.object
                    [ TsEncode.required "reachable"
                        .reachable
                        TsEncode.bool
                    , TsEncode.required "statusCode"
                        .statusCode
                        TsEncode.int
                    ]
            , run = checkStatus
            }

    elm-pages run CheckStatus.elm --url https://example.com
    # { "reachable": true, "statusCode": 200 }

    elm-pages run CheckStatus.elm '{"url":"https://example.com","$cli":{}}'
    # { "reachable": true, "statusCode": 200 }

    elm-pages run CheckStatus.elm --introspect-cli
    # { "name": "CheckStatus",
    #   "description": "Check whether a URL is reachable",
    #   "help": "CheckStatus --url <URL>",
    #   "inputSchema": { ... },
    #   "outputSchema": { ... } }

-}
withSchema :
    { description : String
    , cliOptions : Program.Config cliFlags
    , encoder : TsJson.Encode.Encoder outputType
    , run : cliFlags -> BackendTask FatalError outputType
    }
    -> Script
withSchema ({ cliOptions, encoder, run } as config) =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                cliOptions
                    |> Program.mapConfig
                        (\cliFlags ->
                            run cliFlags
                                |> BackendTask.andThen
                                    (\output ->
                                        log
                                            (output
                                                |> TsJson.Encode.encoder encoder
                                                |> Encode.encode 0
                                            )
                                    )
                        )
        , metadata = Just (introspectionValue config)
        }


introspectionValue :
    { a | description : String, cliOptions : Program.Config cliFlags, encoder : TsJson.Encode.Encoder outputType }
    -> { moduleName : String, path : String }
    -> Encode.Value
introspectionValue config { moduleName, path } =
    let
        helpString : String
        helpString =
            case Program.run config.cliOptions [ "", moduleName, "--help" ] "" Program.WithoutColor of
                Program.SystemMessage _ message ->
                    message

                Program.CustomMatch _ ->
                    ""
    in
    Encode.object
        ([ ( "name", Encode.string moduleName )
         , ( "description", Encode.string config.description )
         , ( "help", Encode.string helpString )
         , ( "inputSchema", Program.toJsonSchema moduleName config.cliOptions )
         , ( "outputSchema"
           , config.encoder
                |> TsJson.Encode.tsType
                |> TsJson.Type.toJsonSchema
           )
         ]
            ++ (if String.isEmpty path then
                    []

                else
                    [ ( "path", Encode.string path ) ]
               )
        )


{-| For internal use by generated code. Most users should not need this.
-}
metadata : { moduleName : String, path : String } -> Script -> Maybe Encode.Value
metadata context script =
    Pages.Internal.Script.metadata context script


{-| Configure the default database file path for `Pages.Db.default` in this script run.

Use this when you want the shared default connection path.
For explicit connection-based paths (for example from CLI options),
use `Pages.Db.open`.

    import Pages.Db
    import Pages.Script as Script

    run : Script
    run =
        Script.withoutCliOptions
            (Pages.Db.update Pages.Db.default (\db -> db)
                |> BackendTask.allowFatal
            )
            |> Script.withDatabasePath ".elm-pages-data/prefs.db.bin"

-}
withDatabasePath : String -> Script -> Script
withDatabasePath dbPath (Pages.Internal.Script.Script script) =
    Pages.Internal.Script.Script
        { toConfig =
            \htmlToString ->
                script.toConfig htmlToString
                    |> Program.mapConfig
                        (\task ->
                            setDatabasePath dbPath
                                |> BackendTask.andThen (\_ -> task)
                        )
        , metadata = script.metadata
        }


{-| Define a TUI (Terminal User Interface) script. The lifecycle mirrors a
Route Module:

  - `data` loads initial data before the TUI starts (normal terminal mode)
  - `init` creates the initial model from loaded data
  - `update` handles terminal events and BackendTask results
  - `view` renders the model to the terminal
  - `subscriptions` declares which terminal events to listen for

Example:

    module Counter exposing (run)

    import Pages.Script as Script exposing (Script)
    import Tui
    import Tui.Effect as Effect
    import Tui.Sub as Sub

    run : Script
    run =
        Script.tui
            { data = BackendTask.succeed ()
            , init = \() -> ( { count = 0 }, Effect.none )
            , update = update
            , view = view
            , subscriptions = \_ -> Sub.onKeyPress KeyPressed
            }

-}
tui :
    { data : BackendTask FatalError data
    , init : data -> ( model, Tui.Effect.Effect msg )
    , update : msg -> model -> ( model, Tui.Effect.Effect msg )
    , view : Tui.Context -> model -> Tui.Screen
    , subscriptions : model -> Tui.Sub.Sub msg
    }
    -> Script
tui config =
    withoutCliOptions
        (config.data
            |> BackendTask.andThen
                (\loadedData ->
                    Tui.Internal.run
                        { init = config.init
                        , update = config.update
                        , view = config.view
                        , subscriptions = config.subscriptions
                        }
                        loadedData
                )
        )


{-| Like [`tui`](#tui), but with CLI option parsing.

    module FileBrowser exposing (run)

    import Cli.Option as Option
    import Cli.OptionsParser as OptionsParser
    import Cli.Program as Program
    import Pages.Script as Script exposing (Script)
    import Tui

    run : Script
    run =
        Script.tuiWithCliOptions
            (Program.config
                |> Program.add
                    (OptionsParser.build identity
                        |> OptionsParser.with
                            (Option.optionalKeywordArg "dir"
                                |> Option.withDefault "."
                            )
                    )
            )
            (\dir ->
                { data = loadFiles dir
                , init = init
                , update = update
                , view = view
                , subscriptions = subscriptions
                }
            )

-}
tuiWithCliOptions :
    Program.Config cliOptions
    ->
        (cliOptions
         ->
            { data : BackendTask FatalError data
            , init : data -> ( model, Tui.Effect.Effect msg )
            , update : msg -> model -> ( model, Tui.Effect.Effect msg )
            , view : Tui.Context -> model -> Tui.Screen
            , subscriptions : model -> Tui.Sub.Sub msg
            }
        )
    -> Script
tuiWithCliOptions cliConfig toTuiConfig =
    withCliOptions cliConfig
        (\cliOptions ->
            let
                config =
                    toTuiConfig cliOptions
            in
            config.data
                |> BackendTask.andThen
                    (\loadedData ->
                        Tui.Internal.run
                            { init = config.init
                            , update = config.update
                            , view = config.view
                            , subscriptions = config.subscriptions
                            }
                            loadedData
                    )
        )


setDatabasePath : String -> BackendTask FatalError ()
setDatabasePath dbPath =
    BackendTask.Internal.Request.request
        { name = "db-set-default-path"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "path", Encode.string dbPath )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


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


{-| Read a single keypress from stdin without requiring Enter.

This is useful for interactive prompts where you want immediate response
to a single key, like confirmation dialogs (y/n) or menu navigation.

    module ConfirmDemo exposing (run)

    import BackendTask

    run : Script
    run =
        Script.withoutCliOptions
            (Script.log "Approve this change? [y/n] "
                |> BackendTask.andThen (\_ -> Script.readKey)
                |> BackendTask.andThen
                    (\key ->
                        if key == "y" then
                            Script.log "Approved!"

                        else
                            Script.log "Rejected."
                    )
            )

Note: Returns the raw key character. Control characters like Ctrl+C will
terminate the process.

When not running in an interactive terminal (e.g., piped input or CI),
falls back to line-buffered input and returns the first character of the line.
This allows scripts to work both interactively and with piped input like
`echo "y" | elm-pages run MyScript.elm`.

-}
readKey : BackendTask error String
readKey =
    BackendTask.Internal.Request.request
        { body = BackendTask.Http.emptyBody
        , expect = BackendTask.Http.expectJson Decode.string
        , name = "readKey"
        }


{-| Like [`readKey`](#readKey), but returns a default value when Enter is pressed.

    Script.log "Continue? [Y/n] "
        |> BackendTask.andThen (\_ -> Script.readKeyWithDefault "y")
        |> BackendTask.andThen
            (\key ->
                if String.toLower key == "y" then
                    continue

                else
                    abort
            )

Useful for prompts where pressing Enter should accept a default option.

-}
readKeyWithDefault : String -> BackendTask error String
readKeyWithDefault default =
    readKey
        |> BackendTask.map
            (\key ->
                if key == "\u{000D}" || key == "\n" then
                    default

                else
                    key
            )


{-| Remove a file. Silently succeeds if the file doesn't exist (like `rm -f`).

    Script.writeFile { path = "temp.txt", body = "..." }
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\_ -> Script.removeFile "temp.txt")

-}
removeFile : String -> BackendTask FatalError ()
removeFile filePath =
    BackendTask.Internal.Request.request
        { name = "delete-file"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "path", Encode.string filePath )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Copy a single file. Auto-creates parent directories of the destination (matching `writeFile` behavior).

    Script.copyFile { from = "src/config.json", to = "dist/config.json" }

-}
copyFile : { from : String, to : String } -> BackendTask FatalError ()
copyFile { from, to } =
    BackendTask.Internal.Request.request
        { name = "copy-file"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "from", Encode.string from )
                    , ( "to", Encode.string to )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Move (rename) a file or directory. Atomic on the same filesystem. Auto-creates parent directories of the destination.

    Script.move { from = "build/output.js", to = "dist/app.js" }

-}
move : { from : String, to : String } -> BackendTask FatalError ()
move { from, to } =
    BackendTask.Internal.Request.request
        { name = "move"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "from", Encode.string from )
                    , ( "to", Encode.string to )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Create a directory.

The `{ recursive : Bool }` flag controls whether parent directories are created (like `mkdir -p`).

    -- Create nested directories
    Script.makeDirectory { recursive = True } "dist/assets/images"

    -- Create a single directory (parent must exist)
    Script.makeDirectory { recursive = False } "output"

-}
makeDirectory : { recursive : Bool } -> String -> BackendTask FatalError ()
makeDirectory { recursive } dirPath =
    BackendTask.Internal.Request.request
        { name = "make-directory"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "path", Encode.string dirPath )
                    , ( "recursive", Encode.bool recursive )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Remove a directory. Silently succeeds if the directory doesn't exist (like `rm -f` on a missing path).

The `{ recursive : Bool }` flag only controls whether non-empty directories can be removed (`rm -r` behavior).
It does not control force semantics.

    -- Remove a directory and all its contents
    Script.removeDirectory { recursive = True } "build"

    -- Remove only if empty
    Script.removeDirectory { recursive = False } "empty-dir"

-}
removeDirectory : { recursive : Bool } -> String -> BackendTask FatalError ()
removeDirectory { recursive } dirPath =
    BackendTask.Internal.Request.request
        { name = "remove-directory"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "path", Encode.string dirPath )
                    , ( "recursive", Encode.bool recursive )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Create a temporary directory with a given prefix. Returns the absolute path to the created directory.

Pairs naturally with `BackendTask.finally` for cleanup:

    Script.makeTempDirectory "my-build-"
        |> BackendTask.andThen
            (\tmpDir ->
                doWork tmpDir
                    |> BackendTask.finally
                        (Script.removeDirectory { recursive = True } tmpDir)
            )

-}
makeTempDirectory : String -> BackendTask FatalError String
makeTempDirectory prefix =
    BackendTask.Internal.Request.request
        { name = "make-temp-directory"
        , body = BackendTask.Http.jsonBody (Encode.string prefix)
        , expect = BackendTask.Http.expectJson Decode.string
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
