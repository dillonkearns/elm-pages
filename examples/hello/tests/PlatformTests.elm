module PlatformTests exposing (suite)

import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as PSelector
import Test.PagesProgram as PagesProgram
import TestApp


suite : Test
suite =
    describe "Hello example"
        [ test "renders the message fetched from example.com" <|
            \() ->
                PagesProgram.expect (TestApp.start "/" BackendTaskTest.init)
                    [ PagesProgram.simulateHttpGet
                        "https://example.com/message"
                        (Encode.object
                            [ ( "message", Encode.string "This is my message!!" ) ]
                        )
                    , PagesProgram.ensureViewHas
                        [ PSelector.text "elm-pages is up and running!"
                        , PSelector.text "The message is: This is my message!!"
                        ]
                    ]
        , test "links to the blog post" <|
            \() ->
                PagesProgram.expect (TestApp.start "/" BackendTaskTest.init)
                    [ PagesProgram.simulateHttpGet
                        "https://example.com/message"
                        (Encode.object
                            [ ( "message", Encode.string "Hello!" ) ]
                        )
                    , PagesProgram.ensureViewHas
                        [ PSelector.tag "a"
                        , PSelector.text "My blog post"
                        ]
                    ]
        ]
