module PageTests exposing (indexTest, counterTest)

{-| Page tests for the end-to-end example.
Run with: elm-pages test-view tests/PageTests.elm
-}

import Route.Counter
import Route.Index
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram exposing (ProgramTest)
import TestApp


indexTest : ProgramTest Route.Index.Model Route.Index.Msg
indexTest =
    PagesProgram.start (TestApp.index {})


counterTest : ProgramTest Route.Counter.Model Route.Counter.Msg
counterTest =
    PagesProgram.start (TestApp.counter {})
        |> PagesProgram.ensureViewHas [ text "The count is:" ]
