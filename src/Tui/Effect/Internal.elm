module Tui.Effect.Internal exposing
    ( Effect(..)
    , Toast(..)
    , none, batch, perform, attempt, exit, exitWithCode
    , toast, info, error, toastMessage, toastIsError
    , map, fold
    , EffectResult(..), toBackendTask
    )

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)


{-| Opaque toast configuration. Build with [`info`](#info) or [`error`](#error).
-}
type Toast
    = Toast { message : String, isError : Bool }


{-| Create an informational toast.
-}
info : String -> Toast
info message =
    Toast { message = message, isError = False }


{-| Create an error toast.
-}
error : String -> Toast
error message =
    Toast { message = message, isError = True }


{-| Get the message text from a toast.
-}
toastMessage : Toast -> String
toastMessage (Toast t) =
    t.message


{-| Check whether a toast is an error toast.
-}
toastIsError : Toast -> Bool
toastIsError (Toast t) =
    t.isError


type Effect msg
    = None
    | Batch (List (Effect msg))
    | RunBackendTask (BackendTask FatalError msg)
    | SuspendBackendTask (BackendTask FatalError msg)
    | Exit
    | ExitWithCode Int
    | ShowToast Toast


none : Effect msg
none =
    None


batch : List (Effect msg) -> Effect msg
batch =
    Batch


perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform toMsg bt =
    RunBackendTask (BackendTask.map toMsg bt)


attempt : (Result FatalError a -> msg) -> BackendTask FatalError a -> Effect msg
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


toast : Toast -> Effect msg
toast =
    ShowToast



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

        SuspendBackendTask bt ->
            SuspendBackendTask (BackendTask.map f bt)

        Exit ->
            Exit

        ExitWithCode code ->
            ExitWithCode code

        ShowToast t ->
            ShowToast t


fold :
    { none : a
    , batch : List (Effect msg) -> a
    , backendTask : BackendTask FatalError msg -> a
    , exit : Int -> a
    , toast : Toast -> a
    }
    -> Effect msg
    -> a
fold handlers effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        None ->
            handlers.none

        Batch effects ->
            handlers.batch effects

        RunBackendTask bt ->
            handlers.backendTask bt

        SuspendBackendTask bt ->
            handlers.backendTask bt

        Exit ->
            handlers.exit 0

        ExitWithCode code ->
            handlers.exit code

        ShowToast t ->
            handlers.toast t


type EffectResult msg
    = EffectDone
    | EffectMsg msg
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
            bt |> BackendTask.map EffectMsg

        SuspendBackendTask bt ->
            bt |> BackendTask.map EffectMsg

        Batch effects ->
            processBatch effects

        ShowToast _ ->
            BackendTask.succeed EffectDone


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

                            EffectMsg _ ->
                                BackendTask.succeed result

                            EffectExit _ ->
                                BackendTask.succeed result
                    )
