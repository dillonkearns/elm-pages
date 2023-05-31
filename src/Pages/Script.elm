module Pages.Script exposing
    ( Script
    , withCliOptions, withoutCliOptions
    , writeFile
    , log
    , Error(..)
    )

{-| An elm-pages Script is a way to execute an `elm-pages` `BackendTask`.

Read more about using the `elm-pages` CLI to run (or bundle) scripts, plus a brief tutorial, at <https://elm-pages.com/docs/elm-pages-scripts>.

@docs Script


## Defining Scripts

@docs withCliOptions, withoutCliOptions


## File System Utilities

@docs writeFile


## Utilities

@docs log


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
