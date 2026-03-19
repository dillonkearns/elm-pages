module ViewerExample exposing (main)

{-| A standalone example of the visual test runner. Compile with:

    npx elm make tests/ViewerExample.elm --output=tests/viewer.html
    open tests/viewer.html

-}

import BackendTask
import BackendTask.Http
import Blog
import Html
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.Viewer as Viewer


main : Program Viewer.Flags Viewer.Model Viewer.Msg
main =
    Viewer.app
        [ ( "Blog: loads and displays posts"
          , blogLoadsPostsTest |> PagesProgram.toSnapshots
          )
        , ( "Blog: GitHub stars"
          , blogStarsTest |> PagesProgram.toSnapshots
          )
        , ( "Counter"
          , counterTest |> PagesProgram.toSnapshots
          )
        ]



-- SAMPLE DATA


samplePosts : Encode.Value
samplePosts =
    Encode.list identity
        [ Encode.object
            [ ( "title", Encode.string "Getting Started with Elm" )
            , ( "author", Encode.string "Dillon Kearns" )
            , ( "excerpt", Encode.string "Learn how to build web apps with Elm." )
            ]
        , Encode.object
            [ ( "title", Encode.string "BackendTask Deep Dive" )
            , ( "author", Encode.string "Dillon Kearns" )
            , ( "excerpt", Encode.string "Understanding the BackendTask abstraction." )
            ]
        , Encode.object
            [ ( "title", Encode.string "Testing Elm Apps" )
            , ( "author", Encode.string "Aaron VonderHaar" )
            , ( "excerpt", Encode.string "Write reliable tests for your Elm code." )
            ]
        ]



-- TESTS


blogLoadsPostsTest =
    PagesProgram.start
        { data = Blog.data
        , init = Blog.init
        , update = Blog.update
        , view = Blog.view
        }
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/posts"
            samplePosts
        |> PagesProgram.ensureViewHas [ Selector.text "Getting Started with Elm" ]
        |> PagesProgram.ensureViewHas [ Selector.text "by Dillon Kearns" ]


blogStarsTest =
    PagesProgram.start
        { data = Blog.data
        , init = Blog.init
        , update = Blog.update
        , view = Blog.view
        }
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/posts"
            samplePosts
        |> PagesProgram.ensureViewHas [ Selector.text "Show GitHub Stars" ]
        |> PagesProgram.clickButton "Show GitHub Stars"
        |> PagesProgram.resolveEffect
            (BackendTaskTest.simulateHttpGet
                "https://api.github.com/repos/dillonkearns/elm-pages"
                (Encode.object [ ( "stargazers_count", Encode.int 4200 ) ])
            )
        |> PagesProgram.ensureViewHas [ Selector.text "elm-pages has 4200 stars" ]



-- COUNTER TEST


type CounterMsg
    = Increment


counterTest =
    PagesProgram.start
        { data = BackendTask.succeed ()
        , init = \() -> ( { count = 0 }, [] )
        , update =
            \msg model ->
                case msg of
                    Increment ->
                        ( { model | count = model.count + 1 }, [] )
        , view =
            \_ model ->
                { title = "Counter: " ++ String.fromInt model.count
                , body =
                    [ Html.div [ Attr.style "padding" "20px", Attr.style "font-family" "sans-serif" ]
                        [ Html.h1 [] [ Html.text "Counter" ]
                        , Html.p [ Attr.style "font-size" "48px", Attr.style "margin" "20px 0" ]
                            [ Html.text (String.fromInt model.count) ]
                        , Html.button
                            [ Html.Events.onClick Increment
                            , Attr.style "padding" "10px 20px"
                            , Attr.style "font-size" "18px"
                            , Attr.style "cursor" "pointer"
                            ]
                            [ Html.text "+1" ]
                        ]
                    ]
                }
        }
        |> PagesProgram.withModelToString Debug.toString
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.clickButton "+1"
