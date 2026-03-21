module Test.PagesProgram.SimulatedSub exposing
    ( SimulatedSub(..)
    , none, batch, port_
    , map
    )

{-| Simulated subscriptions for testing. These parallel Elm's `Sub` type
but are inspectable by the test framework.

Use these with [`PagesProgram.withSimulatedSubscriptions`](Test-PagesProgram#withSimulatedSubscriptions)
to register subscriptions, then send data through them with
[`PagesProgram.simulateIncomingPort`](Test-PagesProgram#simulateIncomingPort).

    import Test.PagesProgram.SimulatedSub as SimulatedSub

    -- In your test setup:
    |> PagesProgram.withSimulatedSubscriptions
        (\model ->
            if model.isConnected then
                SimulatedSub.port_ "websocketData"
                    (Decode.string |> Decode.map GotMessage)
            else
                SimulatedSub.none
        )

@docs SimulatedSub

@docs none, batch, port_

@docs map

-}

import Json.Decode as Decode


{-| A simulated subscription that the test framework can inspect and trigger.
-}
type SimulatedSub msg
    = NoneSub
    | BatchSub (List (SimulatedSub msg))
    | PortSub String (Decode.Decoder msg)


{-| No subscription. Parallels `Sub.none`.
-}
none : SimulatedSub msg
none =
    NoneSub


{-| Combine multiple subscriptions. Parallels `Sub.batch`.
-}
batch : List (SimulatedSub msg) -> SimulatedSub msg
batch =
    BatchSub


{-| Subscribe to an incoming port. Provide the port name and a decoder
that produces your message type.

    SimulatedSub.port_ "websocketData"
        (Decode.string |> Decode.map GotMessage)

-}
port_ : String -> Decode.Decoder msg -> SimulatedSub msg
port_ =
    PortSub


{-| Transform the messages produced by a subscription.
-}
map : (a -> msg) -> SimulatedSub a -> SimulatedSub msg
map f sub =
    case sub of
        NoneSub ->
            NoneSub

        BatchSub subs ->
            BatchSub (List.map (map f) subs)

        PortSub name decoder ->
            PortSub name (Decode.map f decoder)
