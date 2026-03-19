module RealisticExampleTest exposing (suite)

{-| Tests for the Blog app. This is what a real elm-pages user's test file
would look like -- import your route module, pass its functions to
PagesProgram.start, simulate HTTP responses, and assert on the rendered view.
-}

import Blog
import Expect
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector exposing (class, tag, text)
import Test.PagesProgram as PagesProgram


blogApp =
    { data = Blog.data
    , init = Blog.init
    , update = Blog.update
    , view = Blog.view
    }


samplePosts : Encode.Value
samplePosts =
    Encode.list identity
        [ post "Getting Started with Elm" "Dillon Kearns" "Learn how to build web apps with Elm."
        , post "BackendTask Deep Dive" "Dillon Kearns" "Understanding the BackendTask abstraction."
        , post "Testing Elm Apps" "Aaron VonderHaar" "Write reliable tests for your Elm code."
        ]


post : String -> String -> String -> Encode.Value
post title author excerpt =
    Encode.object
        [ ( "title", Encode.string title )
        , ( "author", Encode.string author )
        , ( "excerpt", Encode.string excerpt )
        ]


suite : Test
suite =
    describe "Blog"
        [ test "loads and displays posts from API" <|
            \() ->
                PagesProgram.start blogApp
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/posts"
                        samplePosts
                    |> PagesProgram.ensureViewHas [ tag "h1", text "Blog" ]
                    |> PagesProgram.ensureViewHas [ text "Getting Started with Elm" ]
                    |> PagesProgram.ensureViewHas [ text "BackendTask Deep Dive" ]
                    |> PagesProgram.ensureViewHas [ text "Testing Elm Apps" ]
                    |> PagesProgram.ensureViewHas [ text "by Dillon Kearns" ]
                    |> PagesProgram.done
        , test "clicking Show GitHub Stars fetches and displays count" <|
            \() ->
                PagesProgram.start blogApp
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/posts"
                        samplePosts
                    |> PagesProgram.ensureViewHas [ text "Show GitHub Stars" ]
                    |> PagesProgram.clickButton "Show GitHub Stars"
                    |> PagesProgram.resolveEffect
                        (BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 4200 ) ])
                        )
                    |> PagesProgram.ensureViewHasNot [ text "Show GitHub Stars" ]
                    |> PagesProgram.ensureViewHas [ text "elm-pages has 4200 stars" ]
                    |> PagesProgram.done
        , test "posts render with author attribution" <|
            \() ->
                PagesProgram.start blogApp
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/posts"
                        (Encode.list identity
                            [ post "My Post" "Jane Doe" "A great post." ]
                        )
                    |> PagesProgram.ensureViewHas [ text "My Post" ]
                    |> PagesProgram.ensureViewHas [ class "author", text "by Jane Doe" ]
                    |> PagesProgram.done
        ]
