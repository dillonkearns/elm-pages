module CounterTests exposing (suite)

{-| Integration tests for the Counter route.

Exercises the SimulatedEffect.DispatchMsg pipeline: when the route's
update returns Effect.SendMsg, the message is dispatched through the
Platform update cycle and the view reflects the change.

View in browser: elm-pages dev, then open /\_tests

-}

import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import TestApp


suite : PagesProgram.Test
suite =
    PagesProgram.describe "Counter"
        [ PagesProgram.test "increments and decrements"
            startCounter
            [ PagesProgram.simulateHttpGet "https://api.example.com/counter" counterDataResponse
            , PagesProgram.ensureViewHas [ Selector.text "Count: 0" ]
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ Selector.text "Count: 1" ]
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ Selector.text "Count: 2" ]
            ]
        , PagesProgram.test "fires Effect.SendMsg RecordHistory"
            startCounter
            [ PagesProgram.simulateHttpGet "https://api.example.com/counter" counterDataResponse
            , PagesProgram.ensureViewHas [ Selector.text "No effect yet" ]
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ Selector.text "Effect fired!" ]
            ]
        , PagesProgram.test "increment dispatches RecordHistory as a chained effect"
            startCounter
            [ PagesProgram.simulateHttpGet "https://api.example.com/counter" counterDataResponse
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ Selector.text "Count: 1" ]
            , PagesProgram.ensureViewHas [ Selector.text "History: 1" ]
            ]
        , PagesProgram.test "multiple increments build up history via chained effects"
            startCounter
            [ PagesProgram.simulateHttpGet "https://api.example.com/counter" counterDataResponse
            , PagesProgram.clickButton "+"
            , PagesProgram.clickButton "+"
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ Selector.text "Count: 3" ]
            , PagesProgram.ensureViewHas [ Selector.text "History: 1, 2, 3" ]
            ]
        , PagesProgram.test "reset clears count and history"
            startCounter
            [ PagesProgram.simulateHttpGet "https://api.example.com/counter" counterDataResponse
            , PagesProgram.clickButton "+"
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ Selector.text "Count: 2" ]
            , PagesProgram.clickButton "Reset"
            , PagesProgram.ensureViewHas [ Selector.text "Count: 0" ]
            ]
        ]


startCounter : TestApp.ProgramTest
startCounter =
    TestApp.start "/counter" BackendTaskTest.init


counterDataResponse : Encode.Value
counterDataResponse =
    Encode.object
        [ ( "initialCount", Encode.int 0 )
        , ( "label", Encode.string "My" )
        ]
