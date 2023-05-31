module SimulatedEffect.Time exposing (now)

{-| This module parallels [elm/time's `Time` module](https://package.elm-lang.org/packages/elm/time/1.0.0/Time).
_Pull requests are welcome to add any functions that are missing._

The functions here produce `SimulatedEffect`s instead of `Cmd`s, which are meant to be used
to help you implement the function to provide when using [`ProgramTest.withSimulatedEffects`](ProgramTest#withSimulatedEffects).


# Time

@docs now

-}

import ProgramTest exposing (SimulatedTask)
import SimulatedEffect
import Time


{-| Get the POSIX time at the moment when this task is run.
-}
now : SimulatedTask x Time.Posix
now =
    SimulatedEffect.NowTask SimulatedEffect.Succeed
