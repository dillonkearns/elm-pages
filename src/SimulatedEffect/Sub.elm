module SimulatedEffect.Sub exposing
    ( none, batch
    , map
    )

{-| This module parallels [elm/core's `Platform.Sub` module](https://package.elm-lang.org/packages/elm/core/1.0.2/Platform-Sub).

The functions here produce `SimulatedSub`s instead of `Sub`s, which are meant to be used
to help you implement the function to provide when using [`ProgramTest.withSimulatedSubscriptions`](ProgramTest#withSimulatedSubscriptions).

@docs none, batch

@docs map

-}

import Json.Decode
import ProgramTest exposing (SimulatedEffect, SimulatedSub)
import SimulatedEffect


{-| Tell the runtime that there are no subscriptions.
-}
none : SimulatedSub msg
none =
    SimulatedEffect.NoneSub


{-| When you need to subscribe to multiple things, you can create a `batch` of subscriptions.
-}
batch : List (SimulatedSub msg) -> SimulatedSub msg
batch =
    SimulatedEffect.BatchSub


{-| Transform the messages produced by a subscription.
-}
map : (a -> msg) -> SimulatedSub a -> SimulatedSub msg
map f effect =
    case effect of
        SimulatedEffect.NoneSub ->
            SimulatedEffect.NoneSub

        SimulatedEffect.BatchSub effects ->
            SimulatedEffect.BatchSub (List.map (map f) effects)

        SimulatedEffect.PortSub name decoder ->
            SimulatedEffect.PortSub name (Json.Decode.map f decoder)
