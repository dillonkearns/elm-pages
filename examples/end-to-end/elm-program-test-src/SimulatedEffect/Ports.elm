module SimulatedEffect.Ports exposing (send, subscribe)

{-| This module provides functions that allow you to create `SimulatedEffect`s
that parallel [Elm ports](https://guide.elm-lang.org/interop/ports.html) used in your real program.
This is meant to be used
to help you implement the function to provide when using
[`ProgramTest.withSimulatedEffects`](ProgramTest#withSimulatedEffects)
and [`ProgramTest.withSimulatedSubscriptions`](ProgramTest#withSimulatedSubscriptions).

For a detailed example, see the [“Testing programs with ports” guidebook](https://elm-program-test.netlify.com/ports.html).

@docs send, subscribe

-}

import Json.Decode
import Json.Encode
import ProgramTest exposing (SimulatedEffect, SimulatedSub)
import SimulatedEffect


{-| Creates a `SimulatedEffect` that parallels using an outgoing Elm port.

For example, if your production code uses a port like this:

    port logMessage : String -> Cmd msg

    logMessage "hello"

Then the corresponding `SimulatedEffect` would be:

    SimulatedEffect.Ports.send "logMessage" (Json.Encode.string "hello")

-}
send : String -> Json.Encode.Value -> SimulatedEffect msg
send =
    SimulatedEffect.PortEffect


{-| Creates a `SimulatedSub` that parallels using an incoming Elm port.

For example, if your production code uses a port like this:

    port activeUsers : (List String -> msg) -> Sub msg

    subscriptions : Model -> Sub Msg
    subscriptions model =
        activeUsers OnActiveUsersLoaded

Then the corresponding `SimulatedSub` would be:

    simulatedSubscriptions : Model -> SimulatedSub Msg
    simulatedSubscriptions model =
        SimulatedEffect.Ports.subscribe
            "activeUsers"
            (Json.Decode.list Json.Decode.string)
            OnActiveUsersLoaded

-}
subscribe : String -> Json.Decode.Decoder a -> (a -> msg) -> SimulatedSub msg
subscribe portName decoder toMsg =
    SimulatedEffect.PortSub portName (Json.Decode.map toMsg decoder)
