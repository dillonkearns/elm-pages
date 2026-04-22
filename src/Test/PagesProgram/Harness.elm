module Test.PagesProgram.Harness exposing (start, startWithEffects)

{-| Lightweight entry points for testing `Test.PagesProgram` itself. Not part
of the public package API — the module is intentionally excluded from
`exposed-modules` in `elm.json`.

Framework tests (`tests/PagesProgramTest.elm`) use these to build minimal
programs inline without needing a full `Main.config` from the generated
`TestApp`. Application code should use [`Test.PagesProgram.start`](Test-PagesProgram#start).

@docs start, startWithEffects

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Test.PagesProgram as PagesProgram


{-| Lightweight harness start: build a `ProgramTest` from a minimal
`(data, init, update, view)` config where `init`/`update` return raw
`List (BackendTask FatalError msg)` effects.

    Harness.start
        { data = BackendTask.succeed ()
        , init = \() -> ( {}, [] )
        , update = \_ model -> ( model, [] )
        , view = \() model -> { title = "Home", body = [ Html.text "Hello" ] }
        }

-}
start :
    { data : BackendTask FatalError data
    , init : data -> ( model, List (BackendTask FatalError msg) )
    , update : msg -> model -> ( model, List (BackendTask FatalError msg) )
    , view : data -> model -> { title : String, body : List (Html msg) }
    }
    -> PagesProgram.ProgramTest model msg
start =
    PagesProgram.initialProgramTest


{-| Like [`start`](#start), but for programs that use a custom `Effect` type
instead of raw `List (BackendTask FatalError msg)`. Provide a function that
converts your `Effect` into a list of `BackendTask`s the framework can
simulate.
-}
startWithEffects :
    (effect -> List (BackendTask FatalError msg))
    ->
        { data : BackendTask FatalError data
        , init : data -> ( model, effect )
        , update : msg -> model -> ( model, effect )
        , view : data -> model -> { title : String, body : List (Html msg) }
        }
    -> PagesProgram.ProgramTest model msg
startWithEffects extractEffects config =
    PagesProgram.initialProgramTest
        { data = config.data
        , init =
            \pageData ->
                let
                    ( model, effect ) =
                        config.init pageData
                in
                ( model, extractEffects effect )
        , update =
            \msg model ->
                let
                    ( newModel, effect ) =
                        config.update msg model
                in
                ( newModel, extractEffects effect )
        , view = config.view
        }
