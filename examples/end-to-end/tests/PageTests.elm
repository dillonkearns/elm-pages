module PageTests exposing (indexTest, counterTest, counterClickTest, linksTest)

{-| Page tests for the end-to-end example.
Run with: elm-pages test-view tests/PageTests.elm
-}

import Json.Encode as Encode
import Route.Counter
import Route.Index
import Route.Links
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram exposing (ProgramTest)
import TestApp


{-| Test that the index page renders with simulated data.
The index route loads a greeting from a file, a port greeting, random data,
and the current time.
-}
indexTest : ProgramTest Route.Index.Model Route.Index.Msg
indexTest =
    PagesProgram.start (TestApp.index {})
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/index"
            (Encode.object [])


{-| Test that the counter page renders its initial state. -}
counterTest : ProgramTest Route.Counter.Model Route.Counter.Msg
counterTest =
    PagesProgram.start (TestApp.counter {})
        |> PagesProgram.ensureViewHas [ text "The count is:" ]


{-| Test clicking the counter button and seeing the count update. -}
counterClickTest : ProgramTest Route.Counter.Model Route.Counter.Msg
counterClickTest =
    PagesProgram.start (TestApp.counter {})
        |> PagesProgram.ensureViewHas [ text "The count is:" ]
        |> PagesProgram.ensureViewHas [ text "Loading..." ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"


{-| Test that the links page renders its navigation links. -}
linksTest : ProgramTest Route.Links.Model Route.Links.Msg
linksTest =
    PagesProgram.start (TestApp.links {})
