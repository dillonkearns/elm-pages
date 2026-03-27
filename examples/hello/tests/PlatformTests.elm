module PlatformTests exposing (suite)

import Json.Encode as Encode
import Pages.StaticHttp.Request
import RequestsAndPending
import Test exposing (Test, describe, test)
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp


suite : Test
suite =
    describe "Platform-based tests"
        [ test "renders index with shared layout" <|
            \() ->
                TestApp.start "/" mockData
                    |> PagesProgram.ensureViewHas
                        [ text "elm-pages is up and running!"
                        , text "The message is: This is my message!!"
                        ]
                    |> PagesProgram.done
        , test "shared layout buttons work" <|
            \() ->
                TestApp.start "/" mockData
                    |> PagesProgram.ensureViewHas [ text "Open Menu" ]
                    |> PagesProgram.clickButton "Open Menu"
                    |> PagesProgram.ensureViewHas [ text "Close Menu" ]
                    |> PagesProgram.clickButton "Close Menu"
                    |> PagesProgram.ensureViewHas [ text "Open Menu" ]
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
