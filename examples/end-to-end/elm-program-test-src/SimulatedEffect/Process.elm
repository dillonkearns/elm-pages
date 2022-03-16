module SimulatedEffect.Process exposing (sleep)

{-| This module parallels [elm/core's `Process` module](https://package.elm-lang.org/packages/elm/core/1.0.2/Process).
_Pull requests are welcome to add any functions that are missing._

The functions here produce `SimulatedEffect`s instead of `Cmd`s, which are meant to be used
to help you implement the function to provide when using [`ProgramTest.withSimulatedEffects`](ProgramTest#withSimulatedEffects).


# Processes

@docs sleep

-}

import ProgramTest exposing (SimulatedTask)
import SimulatedEffect


{-| Block progress on the current process for the given number of milliseconds.
-}
sleep : Float -> SimulatedTask x ()
sleep delay =
    SimulatedEffect.SleepTask delay SimulatedEffect.Succeed
