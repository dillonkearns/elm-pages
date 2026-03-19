module PagesProgramTest exposing (all)

import BackendTask
import BackendTask.Http
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Html
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.Html.Selector as Selector
import Test.BackendTask as BackendTaskTest
import Test.PagesProgram as PagesProgram
import Test.Runner


all : Test
all =
    describe "Test.PagesProgram"
        [ describe "Step 1: static page rendering"
            [ test "renders a page with auto-resolved data" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed "Hello, World!"
                        , init = \greeting -> ( { greeting = greeting }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Home", body = [ Html.text model.greeting ] }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Hello, World!" ]
                        |> PagesProgram.done
            , test "renders a page with unit data" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Static content" ] }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Static content" ]
                        |> PagesProgram.done
            , test "can assert on HTML structure" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body =
                                    [ Html.div [ Attr.id "main" ]
                                        [ Html.h1 [] [ Html.text "Welcome" ]
                                        , Html.p [ Attr.class "intro" ] [ Html.text "This is elm-pages" ]
                                        ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.id "main" ]
                        |> PagesProgram.ensureViewHas [ Selector.tag "h1", Selector.text "Welcome" ]
                        |> PagesProgram.ensureViewHas [ Selector.class "intro" ]
                        |> PagesProgram.ensureViewHasNot [ Selector.text "Error" ]
                        |> PagesProgram.done
            , test "data value flows through init into model and view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed { name = "Alice", role = "Admin" }
                        , init = \user -> ( user, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ model ->
                                { title = model.name
                                , body =
                                    [ Html.text (model.name ++ " (" ++ model.role ++ ")")
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Alice (Admin)" ]
                        |> PagesProgram.done
            ]
        , describe "Step 2: data BackendTask with HTTP simulation"
            [ test "resolves data with simulated HTTP GET" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/user"
                                (Decode.field "name" Decode.string)
                                |> BackendTask.allowFatal
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.simulateHttpGet
                            "https://api.example.com/user"
                            (Encode.object [ ( "name", Encode.string "Alice" ) ])
                        |> PagesProgram.ensureViewHas [ Selector.text "Alice" ]
                        |> PagesProgram.done
            , test "done fails when data BackendTask is unresolved" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/user"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.done
                        |> expectFailContaining "still resolving"
            , test "ensureViewHas fails with helpful message when data not resolved" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/user"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Alice" ]
                        |> PagesProgram.done
                        |> expectFailContaining "Cannot check view"
            ]
        , describe "Step 3: user interaction"
            [ test "clicking a button updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { count = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Increment ->
                                        ( { model | count = model.count + 1 }, [] )

                                    Decrement ->
                                        ( { model | count = model.count - 1 }, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.text (String.fromInt model.count)
                                    , Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    , Html.button [ Html.Events.onClick Decrement ] [ Html.text "-1" ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "0" ]
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ Selector.text "1" ]
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ Selector.text "3" ]
                        |> PagesProgram.clickButton "-1"
                        |> PagesProgram.ensureViewHas [ Selector.text "2" ]
                        |> PagesProgram.done
            , test "clickButton fails with helpful message for missing button" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body = [ Html.text "No buttons here" ]
                                }
                        }
                        |> PagesProgram.clickButton "Submit"
                        |> PagesProgram.done
                        |> expectFailContaining "clickButton \"Submit\""
            ]
        , describe "fillIn"
            [ test "typing into an input updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { query = "" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    UpdateQuery q ->
                                        ( { model | query = q }, [] )
                        , view =
                            \_ model ->
                                { title = "Search"
                                , body =
                                    [ Html.input
                                        [ Attr.id "search"
                                        , Attr.value model.query
                                        , Html.Events.onInput UpdateQuery
                                        ]
                                        []
                                    , if String.isEmpty model.query then
                                        Html.text "Type to search..."

                                      else
                                        Html.text ("Searching for: " ++ model.query)
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Type to search..." ]
                        |> PagesProgram.fillIn "search" "elm-pages"
                        |> PagesProgram.ensureViewHas [ Selector.text "Searching for: elm-pages" ]
                        |> PagesProgram.done
            ]
        , describe "resolveEffect"
            [ test "resolves a BackendTask effect from update" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { stars = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    FetchStars ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                                (Decode.field "stargazers_count" Decode.int)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotStars
                                          ]
                                        )

                                    GotStars count ->
                                        ( { model | stars = Just count }, [] )
                        , view =
                            \_ model ->
                                { title = "Stars"
                                , body =
                                    [ case model.stars of
                                        Nothing ->
                                            Html.button [ Html.Events.onClick FetchStars ] [ Html.text "Load Stars" ]

                                        Just count ->
                                            Html.text ("Stars: " ++ String.fromInt count)
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ Selector.text "Load Stars" ]
                        |> PagesProgram.clickButton "Load Stars"
                        |> PagesProgram.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                (Encode.object [ ( "stargazers_count", Encode.int 1234 ) ])
                            )
                        |> PagesProgram.ensureViewHas [ Selector.text "Stars: 1234" ]
                        |> PagesProgram.done
            ]
        ]


type CounterMsg
    = Increment
    | Decrement


type SearchMsg
    = UpdateQuery String


type StarsMsg
    = FetchStars
    | GotStars Int


{-| Assert that an Expectation is a failure containing the given substring.
-}
expectFailContaining : String -> Expectation -> Expectation
expectFailContaining substring expectation =
    case Test.Runner.getFailureReason expectation of
        Nothing ->
            Expect.fail
                ("Expected test to fail with message containing \""
                    ++ substring
                    ++ "\", but it passed."
                )

        Just { description } ->
            if String.contains substring description then
                Expect.pass

            else
                Expect.fail
                    ("Expected failure message to contain \""
                        ++ substring
                        ++ "\", but the actual message was:\n\n"
                        ++ description
                    )
