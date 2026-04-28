module Tui.Effect.Internal exposing
    ( Effect(..)
    , EffectResult(..)
    , attempt
    , batch
    , exit
    , exitWithCode
    , fold
    , map
    , none
    , perform
    , toBackendTask
    )

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)


type Effect msg
    = None
    | Batch (List (Effect msg))
    | RunBackendTask (BackendTask FatalError msg)
    | Exit
    | ExitWithCode Int


none : Effect msg
none =
    None


batch : List (Effect msg) -> Effect msg
batch =
    Batch


perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform toMsg bt =
    RunBackendTask (BackendTask.map toMsg bt)


attempt : (Result error a -> msg) -> BackendTask error a -> Effect msg
attempt toMsg bt =
    RunBackendTask
        (bt
            |> BackendTask.map (\a -> toMsg (Ok a))
            |> BackendTask.onError (\err -> BackendTask.succeed (toMsg (Err err)))
        )


exit : Effect msg
exit =
    Exit


exitWithCode : Int -> Effect msg
exitWithCode =
    ExitWithCode


map : (a -> b) -> Effect a -> Effect b
map f effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        None ->
            None

        Batch effects ->
            Batch (List.map (map f) effects)

        RunBackendTask bt ->
            RunBackendTask (BackendTask.map f bt)

        Exit ->
            Exit

        ExitWithCode code ->
            ExitWithCode code


fold :
    { none : a
    , batch : List (Effect msg) -> a
    , backendTask : BackendTask FatalError msg -> a
    , exit : Int -> a
    }
    -> Effect msg
    -> a
fold handlers effect =
    case effect of
        None ->
            handlers.none

        Batch effects ->
            handlers.batch effects

        RunBackendTask bt ->
            handlers.backendTask bt

        Exit ->
            handlers.exit 0

        ExitWithCode code ->
            handlers.exit code


type EffectResult msg
    = EffectDone
    | EffectMsg msg (Effect msg)
    | EffectExit Int


toBackendTask : Effect msg -> BackendTask FatalError (EffectResult msg)
toBackendTask effect =
    case effect of
        None ->
            BackendTask.succeed EffectDone

        Exit ->
            BackendTask.succeed (EffectExit 0)

        ExitWithCode code ->
            BackendTask.succeed (EffectExit code)

        RunBackendTask bt ->
            bt |> BackendTask.map (\msg -> EffectMsg msg None)

        Batch effects ->
            processBatch effects


processBatch : List (Effect msg) -> BackendTask FatalError (EffectResult msg)
processBatch effects =
    -- elm-review: known-unoptimized-recursion
    case effects of
        [] ->
            BackendTask.succeed EffectDone

        eff :: rest ->
            toBackendTask eff
                |> BackendTask.andThen
                    (\result ->
                        case result of
                            EffectDone ->
                                processBatch rest

                            EffectMsg msg remainingEffect ->
                                BackendTask.succeed
                                    (EffectMsg msg
                                        (continueWith remainingEffect rest)
                                    )

                            EffectExit _ ->
                                BackendTask.succeed result
                    )


continueWith : Effect msg -> List (Effect msg) -> Effect msg
continueWith remainingEffect rest =
    case ( remainingEffect, rest ) of
        ( None, [] ) ->
            None

        ( None, _ ) ->
            Batch rest

        ( _, [] ) ->
            remainingEffect

        _ ->
            Batch (remainingEffect :: rest)
