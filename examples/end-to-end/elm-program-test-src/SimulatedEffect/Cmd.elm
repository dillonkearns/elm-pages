module SimulatedEffect.Cmd exposing
    ( none, batch
    , map
    )

{-| This module parallels [elm/core's `Platform.Cmd` module](https://package.elm-lang.org/packages/elm/core/1.0.2/Platform-Cmd).

The functions here produce `SimulatedEffect`s instead of `Cmd`s, which are meant to be used
to help you implement the function to provide when using [`ProgramTest.withSimulatedEffects`](ProgramTest#withSimulatedEffects).

@docs none, batch

@docs map

-}

import ProgramTest exposing (SimulatedEffect)
import SimulatedEffect
import SimulatedEffect.Task as Task


{-| Tell the runtime that there are no commands.
-}
none : SimulatedEffect msg
none =
    SimulatedEffect.None


{-| When you need the runtime system to perform a couple commands, you can batch them together.
-}
batch : List (SimulatedEffect msg) -> SimulatedEffect msg
batch =
    SimulatedEffect.Batch


{-| Transform the messages produced by a command.
-}
map : (a -> msg) -> SimulatedEffect a -> SimulatedEffect msg
map f effect =
    case effect of
        SimulatedEffect.None ->
            SimulatedEffect.None

        SimulatedEffect.Batch effects ->
            SimulatedEffect.Batch (List.map (map f) effects)

        SimulatedEffect.Task t ->
            t
                |> Task.map f
                |> Task.mapError f
                |> SimulatedEffect.Task

        SimulatedEffect.PortEffect portName value ->
            SimulatedEffect.PortEffect portName value

        SimulatedEffect.PushUrl url ->
            SimulatedEffect.PushUrl url

        SimulatedEffect.ReplaceUrl url ->
            SimulatedEffect.ReplaceUrl url

        SimulatedEffect.Back n ->
            SimulatedEffect.Back n

        SimulatedEffect.Load url ->
            SimulatedEffect.Load url

        SimulatedEffect.Reload skipCache ->
            SimulatedEffect.Reload skipCache
