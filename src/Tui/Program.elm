module Tui.Program exposing
    ( App
    , program, programWithCliOptions
    , programOrScript, programOrScriptWithCliOptions
    , isInteractive
    )

{-| Turn a TUI application into a `Pages.Script.Script` that elm-pages can run.

A TUI app is described by a flat record: a `data` BackendTask that resolves
before `init`, followed by the four standard TEA fields. Both hand-written
apps and `Tui.Layout.compileApp` output fit this shape.

    run : Script
    run =
        Tui.Program.program
            { data = BackendTask.succeed ()
            , init = \() -> ( { count = 0 }, Effect.none )
            , update = update
            , view = view
            , subscriptions = \_ -> Tui.Sub.onKeyPress KeyPressed
            }


## The App record

@docs App


## Running a TUI

@docs program, programWithCliOptions


## TUI or script

For programs that make sense both interactively and non-interactively (an
agent piping output, a CI run), provide a `script` branch alongside the
`tui`. At runtime, `when` decides which path to take.

@docs programOrScript, programOrScriptWithCliOptions


## Detection

@docs isInteractive

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Pages.Internal.Script
import Tui exposing (Context, Screen)
import Tui.Effect as Effect
import Tui.Internal
import Tui.Sub


{-| A runnable TUI application.

The `data` field resolves before `init` runs (while the terminal is still in
normal mode), so you can read files, fetch data, or run shell commands without
fighting the TUI render loop. The remaining fields are a standard TEA quartet,
except `update` returns a [`Tui.Effect`](Tui-Effect#Effect) instead of `Cmd` so
you can run `BackendTask`s from the update cycle.

Build one directly, or use [`Tui.Layout.compileApp`](Tui-Layout#compileApp)
from the `tui-widgets` package to compile a declarative layout description
into the same shape.

-}
type alias App data model msg =
    { data : BackendTask FatalError data
    , init : data -> ( model, Effect.Effect msg )
    , update : msg -> model -> ( model, Effect.Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Tui.Sub.Sub msg
    }


{-| Run a TUI as a Script. No CLI options, no script fallback — just a TUI.

    run : Script
    run =
        Tui.Program.program
            { data = BackendTask.succeed ()
            , init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }

-}
program : App data model msg -> Pages.Internal.Script.Script
program app =
    scriptFromBackendTask (runApp app)


{-| Run a TUI as a Script, with CLI option parsing.

    run : Script
    run =
        Tui.Program.programWithCliOptions
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
programWithCliOptions :
    Program.Config cliOptions
    -> (cliOptions -> App data model msg)
    -> Pages.Internal.Script.Script
programWithCliOptions config toApp =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                config
                    |> Program.mapConfig (\cliOptions -> runApp (toApp cliOptions))
        , metadata = Nothing
        }


{-| Run a TUI when the terminal is interactive, fall back to a non-interactive
script otherwise. `when` decides which path to take — pass
[`isInteractive`](#isInteractive) for the standard isatty + CI + NO_COLOR
heuristic, or your own `BackendTask FatalError Bool` for custom detection.

    run : Script
    run =
        Tui.Program.programOrScript
            { tui =
                { data = loadCommits
                , init = init
                , update = update
                , view = view
                , subscriptions = subscriptions
                }
            , script =
                loadCommits
                    |> BackendTask.andThen (\commits -> Script.log (summarize commits))
            , when = Tui.Program.isInteractive
            }

The `tui`'s `data` only runs on the TUI path; the `script` path runs
independently so it can do its own loading or be a trivial no-op.

-}
programOrScript :
    { tui : App data model msg
    , script : BackendTask FatalError ()
    , when : BackendTask FatalError Bool
    }
    -> Pages.Internal.Script.Script
programOrScript { tui, script, when } =
    scriptFromBackendTask (chooseBranch when (runApp tui) script)


{-| Like [`programOrScript`](#programOrScript), but with CLI option parsing.
-}
programOrScriptWithCliOptions :
    Program.Config cliOptions
    ->
        (cliOptions
         ->
            { tui : App data model msg
            , script : BackendTask FatalError ()
            , when : BackendTask FatalError Bool
            }
        )
    -> Pages.Internal.Script.Script
programOrScriptWithCliOptions config toBranches =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                config
                    |> Program.mapConfig
                        (\cliOptions ->
                            let
                                branches :
                                    { tui : App data model msg
                                    , script : BackendTask FatalError ()
                                    , when : BackendTask FatalError Bool
                                    }
                                branches =
                                    toBranches cliOptions
                            in
                            chooseBranch branches.when (runApp branches.tui) branches.script
                        )
        , metadata = Nothing
        }


{-| The standard interactive-terminal heuristic: `True` if stdout and stdin
are both TTYs, `CI` and `NO_COLOR` are unset, and `TERM` is not `dumb`.

Use this as the `when` field of [`programOrScript`](#programOrScript). If you
need different rules (for example, always TUI regardless of pipes), supply
your own `BackendTask FatalError Bool` instead.

    -- Default:
    when = Tui.Program.isInteractive

    -- Force TUI:
    when = BackendTask.succeed True

    -- Opt out of TUI when a flag is set, otherwise use the default:
    when =
        if cliOptions.plain then
            BackendTask.succeed False

        else
            Tui.Program.isInteractive

-}
isInteractive : BackendTask FatalError Bool
isInteractive =
    BackendTask.Internal.Request.request
        { name = "tui-is-interactive"
        , body = BackendTask.Http.emptyBody
        , expect = Decode.bool
        }



-- INTERNAL


scriptFromBackendTask : BackendTask FatalError () -> Pages.Internal.Script.Script
scriptFromBackendTask task =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                Program.config
                    |> Program.add (OptionsParser.build ())
                    |> Program.mapConfig (\() -> task)
        , metadata = Nothing
        }


runApp : App data model msg -> BackendTask FatalError ()
runApp app =
    app.data
        |> BackendTask.quiet
        |> BackendTask.andThen
            (\loadedData ->
                Tui.Internal.run
                    { init = app.init
                    , update = app.update
                    , view = app.view
                    , subscriptions = app.subscriptions
                    }
                    loadedData
            )


chooseBranch :
    BackendTask FatalError Bool
    -> BackendTask FatalError ()
    -> BackendTask FatalError ()
    -> BackendTask FatalError ()
chooseBranch when tuiBranch scriptBranch =
    when
        |> BackendTask.andThen
            (\interactive ->
                if interactive then
                    tuiBranch

                else
                    scriptBranch
            )
