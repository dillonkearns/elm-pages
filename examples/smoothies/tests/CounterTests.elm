module CounterTests exposing
    ( incrementTest
    , effectFiredTest
    , chainedEffectTest
    , multipleChainedEffectsTest
    , resetTest
    )

{-| Integration tests for the Counter route.

Exercises the SimulatedEffect.DispatchMsg pipeline: when the route's
update returns Effect.SendMsg, the message is dispatched through the
Platform update cycle and the view reflects the change.

View in browser: elm-pages test-view tests/CounterTests.elm

-}

import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.PagesProgram as PagesProgram
import Test.Html.Selector as Selector
import TestApp


counterDataResponse : Encode.Value
counterDataResponse =
    Encode.object
        [ ( "initialCount", Encode.int 0 )
        , ( "label", Encode.string "My" )
        ]


startCounter : TestApp.ProgramTest
startCounter =
    TestApp.start "/counter" BackendTaskTest.init
        |> PagesProgram.simulateHttpGet "https://api.example.com/counter" counterDataResponse


{-| Basic increment works (count updates via direct model change).
-}
incrementTest : TestApp.ProgramTest
incrementTest =
    startCounter
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 0" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 1" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 2" ]


{-| Effect.SendMsg RecordHistory fires and updates the model.
This is the core SimulatedEffect.DispatchMsg test.
-}
effectFiredTest : TestApp.ProgramTest
effectFiredTest =
    startCounter
        |> PagesProgram.ensureViewHas [ Selector.text "No effect yet" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ Selector.text "Effect fired!" ]


{-| Increment dispatches RecordHistory as a chained effect.
Verifies the full pipeline: Effect.SendMsg -> testPerform ->
SimulatedEffect.DispatchMsg -> Platform.UserMsg -> route update.
-}
chainedEffectTest : TestApp.ProgramTest
chainedEffectTest =
    startCounter
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 1" ]
        |> PagesProgram.ensureViewHas [ Selector.text "History: 1" ]


{-| Multiple increments build up history via chained effects.
Each click dispatches RecordHistory which appends the current count.
-}
multipleChainedEffectsTest : TestApp.ProgramTest
multipleChainedEffectsTest =
    startCounter
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 3" ]
        |> PagesProgram.ensureViewHas [ Selector.text "History: 1, 2, 3" ]


{-| Reset clears count and history (uses Effect.none, no chaining).
-}
resetTest : TestApp.ProgramTest
resetTest =
    startCounter
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 2" ]
        |> PagesProgram.clickButton "Reset"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 0" ]
