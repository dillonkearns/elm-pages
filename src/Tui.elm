module Tui exposing
    ( Program, program, programWithCliOptions
    , Mode(..), programOrScript, isInteractive
    , Context, ColorProfile(..)
    )

{-| Run a TUI (Terminal User Interface) as an elm-pages script.

A TUI application is a flat record: a `data` BackendTask that resolves before
`init`, followed by the four standard TEA fields. Both hand-written apps and
[`Tui.Layout.compileApp`](Tui-Layout#compileApp) from the `tui-widgets` package
produce this shape.

    import Tui
    import Tui.Screen as Screen
    import Tui.Sub

    run : Script
    run =
        Tui.program
            { data = BackendTask.succeed ()
            , init = \() -> ( { count = 0 }, Effect.none )
            , update = update
            , view = view
            , subscriptions = \_ -> Tui.Sub.onKeyPress KeyPressed
            }


## Running a TUI

@docs Program, program, programWithCliOptions


## TUI or CLI

For programs that make sense both interactively and non-interactively (an
agent piping output, a CI run), use [`programOrScript`](#programOrScript) to
provide a `script` branch alongside the `tui`. At runtime, `mode` decides
which path to take — [`isInteractive`](#isInteractive) is the standard
heuristic (isatty + CI + NO_COLOR) for common use.

@docs Mode, programOrScript, isInteractive


## Terminal Context

Passed to your `view` function. Use `colorProfile` to adapt themes for
different terminal capabilities.

@docs Context, ColorProfile

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Cli.OptionsParser as OptionsParser
import Cli.Program as CliProgram
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.Script
import Tui.Effect as Effect
import Tui.Effect.Internal as EffectInternal
import Tui.Screen exposing (Screen)
import Tui.Sub
import Tui.Sub.Internal as SubInternal



-- CONTEXT


{-| Read-only terminal context provided to `view`.
-}
type alias Context =
    { width : Int
    , height : Int
    , colorProfile : ColorProfile
    }


{-| Terminal color capability, detected at init from environment variables.
Follows charmbracelet/colorprofile's detection precedence:
`$NO_COLOR` -> `$COLORTERM` -> known terminals -> `$TERM` suffix -> default.

The renderer automatically degrades colors based on the profile — the Elm app
can always use the highest fidelity colors and they'll be converted. But this
field lets apps adapt themes (e.g., use different palettes for 16-color).

    view ctx model =
        case ctx.colorProfile of
            Tui.TrueColor -> richColorView model
            _ -> basicColorView model

-}
type ColorProfile
    = TrueColor
    | Color256
    | Color16
    | Mono



-- PROGRAM


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
type alias Program data model msg =
    { data : BackendTask FatalError data
    , init : data -> ( model, Effect.Effect msg )
    , update : msg -> model -> ( model, Effect.Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Tui.Sub.Sub msg
    }


{-| Run a TUI as a Script. No CLI options, no script fallback — just a TUI.
-}
program : Program data model msg -> Pages.Internal.Script.Script
program app =
    scriptFromBackendTask (runProgram app)


{-| Run a TUI as a Script, with CLI option parsing.

    run : Script
    run =
        Tui.programWithCliOptions
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
    CliProgram.Config cliOptions
    -> (cliOptions -> Program data model msg)
    -> Pages.Internal.Script.Script
programWithCliOptions config toApp =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                config
                    |> CliProgram.mapConfig
                        (\cliOptions -> runProgram (toApp cliOptions))
        , metadata = Nothing
        }


{-| Which path should a [`programOrScript`](#programOrScript) take — the
interactive TUI, or the plain `BackendTask` fallback?

    type Mode
        = Tui
        | Cli

Returned from `mode : BackendTask FatalError Mode` in `programOrScript`.
Use [`isInteractive`](#isInteractive) for the standard heuristic, or build
your own `BackendTask` to decide.

-}
type Mode
    = Tui
    | Cli


{-| Run a TUI when the terminal is interactive, fall back to a non-interactive
script otherwise. The `mode` BackendTask decides which path to take — pass
[`isInteractive`](#isInteractive) for the standard isatty + CI + NO_COLOR
heuristic, or your own `BackendTask FatalError Mode` for custom detection.

    run : Script
    run =
        Tui.programOrScript
            (Program.config |> Program.add ...)
            (\flags ->
                { tui =
                    { data = loadCommits
                    , init = init
                    , update = update
                    , view = view
                    , subscriptions = subscriptions
                    }
                , script =
                    loadCommits
                        |> BackendTask.andThen
                            (\commits -> Script.log (summarize commits))
                , mode = Tui.isInteractive
                }
            )

The `tui`'s `data` only runs on the TUI path; the `script` path runs
independently so it can do its own loading or be a trivial no-op.

-}
programOrScript :
    CliProgram.Config cliOptions
    ->
        (cliOptions
         ->
            { tui : Program data model msg
            , script : BackendTask FatalError ()
            , mode : BackendTask FatalError Mode
            }
        )
    -> Pages.Internal.Script.Script
programOrScript config toBranches =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                config
                    |> CliProgram.mapConfig
                        (\cliOptions ->
                            let
                                branches :
                                    { tui : Program data model msg
                                    , script : BackendTask FatalError ()
                                    , mode : BackendTask FatalError Mode
                                    }
                                branches =
                                    toBranches cliOptions
                            in
                            chooseBranch branches.mode
                                (runProgram branches.tui)
                                branches.script
                        )
        , metadata = Nothing
        }


{-| The standard interactive-terminal heuristic: returns `Tui` if stdout and
stdin are both TTYs and `CI`, `NO_COLOR`, and `TERM=dumb` are all unset.
Otherwise returns `Cli`.

Use this as the `mode` field of [`programOrScript`](#programOrScript). If
you need different rules (for example, always TUI regardless of pipes),
supply your own `BackendTask FatalError Mode` instead.

    -- Default:
    mode = Tui.isInteractive

    -- Force TUI:
    mode = BackendTask.succeed Tui.Tui

    -- Opt out of TUI when a flag is set, otherwise use the default:
    mode =
        if cliOptions.plain then
            BackendTask.succeed Tui.Cli

        else
            Tui.isInteractive

-}
isInteractive : BackendTask FatalError Mode
isInteractive =
    BackendTask.Internal.Request.request
        { name = "tui-is-interactive"
        , body = BackendTask.Http.emptyBody
        , expect =
            Decode.bool
                |> Decode.map
                    (\b ->
                        if b then
                            Tui

                        else
                            Cli
                    )
        }



-- INTERNAL: Script construction + run loop


scriptFromBackendTask : BackendTask FatalError () -> Pages.Internal.Script.Script
scriptFromBackendTask task =
    Pages.Internal.Script.Script
        { toConfig =
            \_ ->
                CliProgram.config
                    |> CliProgram.add (OptionsParser.build ())
                    |> CliProgram.mapConfig (\() -> task)
        , metadata = Nothing
        }


runProgram : Program data model msg -> BackendTask FatalError ()
runProgram app =
    app.data
        |> BackendTask.quiet
        |> BackendTask.andThen
            (\loadedData ->
                tuiInit
                    |> BackendTask.andThen
                        (\context ->
                            let
                                ( initialModel, initialEffect ) =
                                    app.init loadedData

                                ( modelWithContext, contextEffect ) =
                                    applyContextUpdate app.update
                                        (app.subscriptions initialModel)
                                        context
                                        initialModel
                            in
                            processEffectsThenRenderAndWait app
                                context
                                modelWithContext
                                (Effect.batch [ initialEffect, contextEffect ])
                        )
            )


tuiInit : BackendTask FatalError Context
tuiInit =
    BackendTask.Internal.Request.request
        { name = "tui-init"
        , body = BackendTask.Http.emptyBody
        , expect =
            Decode.map3 (\w h cp -> { width = w, height = h, colorProfile = cp })
                (Decode.field "width" Decode.int)
                (Decode.field "height" Decode.int)
                (Decode.field "colorProfile" decodeColorProfile)
        }


tuiRenderAndWait :
    Screen
    -> Tui.Sub.Sub msg
    -> BackendTask FatalError { events : List Decode.Value, width : Int, height : Int }
tuiRenderAndWait screen sub =
    BackendTask.Internal.Request.request
        { name = "tui-render-and-wait"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "screen", Tui.Screen.encodeScreen screen )
                    , ( "interests", SubInternal.getInterests sub )
                    , ( "tickIntervals", Encode.list Encode.int (SubInternal.getTickIntervals sub) )
                    ]
                )
        , expect =
            Decode.map2 (\evts wh -> { events = evts, width = wh.width, height = wh.height })
                (Decode.oneOf
                    [ Decode.field "events" (Decode.list Decode.value)
                    , Decode.field "event" Decode.value |> Decode.map List.singleton
                    ]
                )
                (Decode.map2 (\w h -> { width = w, height = h })
                    (Decode.field "width" Decode.int)
                    (Decode.field "height" Decode.int)
                )
        }


tuiExit : Int -> BackendTask FatalError ()
tuiExit code =
    BackendTask.Internal.Request.request
        { name = "tui-exit"
        , body = BackendTask.Http.jsonBody (Encode.int code)
        , expect = Decode.succeed ()
        }


decodeColorProfile : Decode.Decoder ColorProfile
decodeColorProfile =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "truecolor" ->
                        Decode.succeed TrueColor

                    "256" ->
                        Decode.succeed Color256

                    "16" ->
                        Decode.succeed Color16

                    "mono" ->
                        Decode.succeed Mono

                    _ ->
                        Decode.succeed Color16
            )


processEffectsThenRenderAndWait :
    Program data model msg
    -> Context
    -> model
    -> Effect.Effect msg
    -> BackendTask FatalError ()
processEffectsThenRenderAndWait app context model effect =
    -- elm-review: known-unoptimized-recursion
    EffectInternal.toBackendTask effect
        |> BackendTask.quiet
        |> BackendTask.andThen
            (\result ->
                case result of
                    EffectInternal.EffectDone ->
                        renderAndWait app context model

                    EffectInternal.EffectMsg msg ->
                        let
                            ( newModel, newEffect ) =
                                app.update msg model
                        in
                        processEffectsThenRenderAndWait app context newModel newEffect

                    EffectInternal.EffectExit code ->
                        tuiExit code
                            |> BackendTask.andThen
                                (\() ->
                                    if code /= 0 then
                                        BackendTask.fail
                                            (FatalError.build
                                                { title = "TUI exited with code " ++ String.fromInt code
                                                , body = ""
                                                }
                                            )

                                    else
                                        BackendTask.succeed ()
                                )
            )


renderAndWait :
    Program data model msg
    -> Context
    -> model
    -> BackendTask FatalError ()
renderAndWait app context model =
    -- elm-review: known-unoptimized-recursion
    let
        screen : Screen
        screen =
            app.view context model

        sub : Tui.Sub.Sub msg
        sub =
            app.subscriptions model
    in
    tuiRenderAndWait screen sub
        |> BackendTask.andThen
            (\response ->
                let
                    newContext : Context
                    newContext =
                        { width = response.width
                        , height = response.height
                        , colorProfile = context.colorProfile
                        }

                    ( modelAfterContext, contextEffects ) =
                        if newContext.width /= context.width || newContext.height /= context.height then
                            applyContextUpdate app.update sub newContext model
                                |> Tuple.mapSecond effectToList

                        else
                            ( model, [] )
                in
                processBatchedEventsHelp app sub newContext modelAfterContext contextEffects response.events
            )


processBatchedEventsHelp :
    Program data model msg
    -> Tui.Sub.Sub msg
    -> Context
    -> model
    -> List (Effect.Effect msg)
    -> List Decode.Value
    -> BackendTask FatalError ()
processBatchedEventsHelp app sub context model accEffects events =
    -- elm-review: known-unoptimized-recursion
    case events of
        [] ->
            case accEffects of
                [] ->
                    renderAndWait app context model

                _ ->
                    processEffectsThenRenderAndWait app
                        context
                        model
                        (Effect.batch (List.reverse accEffects))

        rawValue :: rest ->
            let
                rawEvent : SubInternal.RawEvent
                rawEvent =
                    decodeRawEvent rawValue
            in
            case rawEvent of
                SubInternal.RawResize ->
                    processBatchedEventsHelp app sub context model accEffects rest

                _ ->
                    let
                        ( newModel, newAccEffects ) =
                            List.foldl
                                (\msg ( m, effs ) ->
                                    let
                                        ( m2, newEffect ) =
                                            app.update msg m
                                    in
                                    ( m2, newEffect :: effs )
                                )
                                ( model, accEffects )
                                (SubInternal.routeEvents sub rawEvent)
                    in
                    processBatchedEventsHelp app sub context newModel newAccEffects rest


decodeRawEvent : Decode.Value -> SubInternal.RawEvent
decodeRawEvent value =
    case Decode.decodeValue SubInternal.decodeRawEvent value of
        Ok event ->
            event

        Err _ ->
            SubInternal.RawResize


applyContextUpdate :
    (msg -> model -> ( model, Effect.Effect msg ))
    -> Tui.Sub.Sub msg
    -> Context
    -> model
    -> ( model, Effect.Effect msg )
applyContextUpdate update sub context model =
    SubInternal.routeEvents sub (SubInternal.RawContext { width = context.width, height = context.height })
        |> List.foldl
            (\msg ( m, accEffect ) ->
                let
                    ( newModel, newEffect ) =
                        update msg m
                in
                ( newModel, Effect.batch [ accEffect, newEffect ] )
            )
            ( model, Effect.none )


effectToList : Effect.Effect msg -> List (Effect.Effect msg)
effectToList effect =
    Effect.fold
        { none = []
        , batch = \_ -> [ effect ]
        , backendTask = \_ -> [ effect ]
        , exit = \_ -> [ effect ]
        }
        effect


chooseBranch :
    BackendTask FatalError Mode
    -> BackendTask FatalError ()
    -> BackendTask FatalError ()
    -> BackendTask FatalError ()
chooseBranch mode tuiBranch scriptBranch =
    mode
        |> BackendTask.andThen
            (\m ->
                case m of
                    Tui ->
                        tuiBranch

                    Cli ->
                        scriptBranch
            )
