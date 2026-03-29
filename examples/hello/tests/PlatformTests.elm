module PlatformTests exposing (suite)

import Json.Encode as Encode
import Pages.StaticHttp.Request
import RequestsAndPending
import Test exposing (Test, describe, test)
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.Selector as PSelector
import TestApp


suite : Test
suite =
    describe "Platform-based tests"
        [ test "renders index with shared layout" <|
            \() ->
                TestApp.start "/" mockData
                    |> PagesProgram.ensureViewHas
                        [ PSelector.text "elm-pages is up and running!"
                        , PSelector.text "The message is: This is my message!!"
                        ]
                    |> PagesProgram.done
        , test "shared layout buttons work" <|
            \() ->
                TestApp.start "/" mockData
                    |> PagesProgram.ensureViewHas [ PSelector.text "Open Menu" ]
                    |> PagesProgram.clickButton "Open Menu"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Close Menu" ]
                    |> PagesProgram.clickButton "Close Menu"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Open Menu" ]
                    |> PagesProgram.done
        ]


mockData : Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response
mockData request =
    RequestsAndPending.Response Nothing
        (RequestsAndPending.JsonBody
            (Encode.object
                [ ( "message", Encode.string "This is my message!!" )
                ]
            )
        )
        |> Just
