module PagesProgramTest exposing (all)

import BackendTask
import BackendTask.Http
import CookieJar
import Dict
import Expect exposing (Expectation)
import FatalError
import Html
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Json.Encode as Encode
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.PagesProgram.Selector as PSelector exposing (AssertionSelector(..))
import Test.BackendTask as BackendTaskTest
import Test.BackendTask exposing (HttpError(..))
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.SimulatedEffect as SimulatedEffect
import Test.PagesProgram.SimulatedSub as SimulatedSub
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
                        |> PagesProgram.ensureViewHas [ PSelector.text "Hello, World!" ]
                        |> PagesProgram.done
            , test "renders a page with unit data" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Static content" ] }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Static content" ]
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
                        |> PagesProgram.ensureViewHas [ PSelector.id "main" ]
                        |> PagesProgram.ensureViewHas [ PSelector.tag "h1", PSelector.text "Welcome" ]
                        |> PagesProgram.ensureViewHas [ PSelector.class "intro" ]
                        |> PagesProgram.ensureViewHasNot [ PSelector.text "Error" ]
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
                        |> PagesProgram.ensureViewHas [ PSelector.text "Alice (Admin)" ]
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
                        |> PagesProgram.ensureViewHas [ PSelector.text "Alice" ]
                        |> PagesProgram.done
            , test "resolves multiple sequential HTTP POST requests with different bodies to the same URL" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.map2 (\a b -> a ++ " & " ++ b)
                                (BackendTask.Http.request
                                    { url = "https://api.example.com/graphql"
                                    , method = "POST"
                                    , headers = []
                                    , body = BackendTask.Http.jsonBody (Encode.object [ ( "query", Encode.string "{ users { name } }" ) ])
                                    , retries = Nothing
                                    , timeoutInMs = Nothing
                                    }
                                    (BackendTask.Http.expectJson (Decode.at [ "data", "users" ] (Decode.index 0 (Decode.field "name" Decode.string))))
                                    |> BackendTask.allowFatal
                                )
                                (BackendTask.Http.request
                                    { url = "https://api.example.com/graphql"
                                    , method = "POST"
                                    , headers = []
                                    , body = BackendTask.Http.jsonBody (Encode.object [ ( "query", Encode.string "{ items { title } }" ) ])
                                    , retries = Nothing
                                    , timeoutInMs = Nothing
                                    }
                                    (BackendTask.Http.expectJson (Decode.at [ "data", "items" ] (Decode.index 0 (Decode.field "title" Decode.string))))
                                    |> BackendTask.allowFatal
                                )
                        , init = \combined -> ( { text = combined }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Test", body = [ Html.text model.text ] }
                        }
                        |> PagesProgram.simulateHttpPost
                            "https://api.example.com/graphql"
                            (Encode.object [ ( "data", Encode.object [ ( "users", Encode.list identity [ Encode.object [ ( "name", Encode.string "Alice" ) ] ] ) ] ) ])
                        |> PagesProgram.simulateHttpPost
                            "https://api.example.com/graphql"
                            (Encode.object [ ( "data", Encode.object [ ( "items", Encode.list identity [ Encode.object [ ( "title", Encode.string "Widget" ) ] ] ) ] ) ])
                        |> PagesProgram.ensureViewHas [ PSelector.text "Alice & Widget" ]
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
                        |> PagesProgram.ensureViewHas [ PSelector.text "Alice" ]
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
                        |> PagesProgram.ensureViewHas [ PSelector.text "0" ]
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ PSelector.text "1" ]
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ PSelector.text "3" ]
                        |> PagesProgram.clickButton "-1"
                        |> PagesProgram.ensureViewHas [ PSelector.text "2" ]
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
                        |> PagesProgram.ensureViewHas [ PSelector.text "Type to search..." ]
                        |> PagesProgram.fillIn "search" "search" "elm-pages"
                        |> PagesProgram.ensureViewHas [ PSelector.text "Searching for: elm-pages" ]
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
                        |> PagesProgram.ensureViewHas [ PSelector.text "Load Stars" ]
                        |> PagesProgram.clickButton "Load Stars"
                        |> PagesProgram.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                (Encode.object [ ( "stargazers_count", Encode.int 1234 ) ])
                            )
                        |> PagesProgram.ensureViewHas [ PSelector.text "Stars: 1234" ]
                        |> PagesProgram.done
            ]
        , describe "check"
            [ test "checking a checkbox updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { agreed = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    ToggleAgreed checked ->
                                        ( { model | agreed = checked }, [] )
                        , view =
                            \_ model ->
                                { title = "Form"
                                , body =
                                    [ Html.label [ Attr.for "agree" ] [ Html.text "I agree" ]
                                    , Html.input
                                        [ Attr.id "agree"
                                        , Attr.type_ "checkbox"
                                        , Attr.checked model.agreed
                                        , Html.Events.onCheck ToggleAgreed
                                        ]
                                        []
                                    , if model.agreed then
                                        Html.text "Terms accepted"

                                      else
                                        Html.text "Please accept terms"
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Please accept terms" ]
                        |> PagesProgram.check "agree" "I agree" True
                        |> PagesProgram.ensureViewHas [ PSelector.text "Terms accepted" ]
                        |> PagesProgram.done
            ]
        , describe "Snapshots"
            [ test "toSnapshots records init snapshot" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal [ "start" ]
            , test "toSnapshots records each interaction" <|
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
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.ensureViewHas [ PSelector.text "2" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal [ "start", "clickButton \"+1\"", "clickButton \"+1\"", "ensureViewHas text \"2\"" ]
            , test "snapshots contain rendered HTML" <|
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
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Count: " ++ String.fromInt model.count
                                , body =
                                    [ Html.text ("Count: " ++ String.fromInt model.count)
                                    , Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.toSnapshots
                        |> List.map .title
                        |> Expect.equal [ "Count: 0", "Count: 1" ]
            , test "error snapshots include the error" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.clickButton "Missing"
                        |> PagesProgram.toSnapshots
                        |> List.length
                        |> Expect.equal 2
            , test "snapshot labels show selector details for ensureViewHas" <|
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
                                    [ Html.div [ Attr.id "main", Attr.class "counter" ]
                                        [ Html.text (String.fromInt model.count) ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "0" ]
                        |> PagesProgram.ensureViewHas [ PSelector.id "main" ]
                        |> PagesProgram.ensureViewHas [ PSelector.class "counter" ]
                        |> PagesProgram.ensureViewHas [ PSelector.tag "div" ]
                        |> PagesProgram.ensureViewHasNot [ PSelector.text "Error" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas text \"0\""
                            , "ensureViewHas #main"
                            , "ensureViewHas .counter"
                            , "ensureViewHas <div>"
                            , "ensureViewHasNot text \"Error\""
                            ]
            , test "snapshot labels show multiple selectors comma-separated" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body =
                                    [ Html.h1 [ Attr.class "title" ] [ Html.text "Welcome" ] ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.tag "h1", PSelector.text "Welcome" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas <h1>, text \"Welcome\""
                            ]
            , test "clickButtonWith snapshot labels show selector details" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { clicked = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Increment ->
                                        ( { model | clicked = True }, [] )

                                    Decrement ->
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Home"
                                , body =
                                    [ Html.button [ Attr.class "submit-btn", Html.Events.onClick Increment ] [ Html.text "Go" ] ]
                                }
                        }
                        |> PagesProgram.clickButtonWith [ PSelector.class "submit-btn" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "clickButtonWith .submit-btn"
                            ]
            , test "withinFind adds scope label to assertion snapshots" <|
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
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Sections"
                                , body =
                                    [ Html.div [ Attr.id "counter" ]
                                        [ Html.text (String.fromInt model.count)
                                        , Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                        ]
                                    ]
                                }
                        }
                        |> PagesProgram.withinFind
                            [ PSelector.id "counter" ]
                            (PagesProgram.ensureViewHas [ PSelector.text "0" ])
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas text \"0\" (within #counter)"
                            ]
            , test "nested withinFind shows chained scope labels" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Nested"
                                , body =
                                    [ Html.div [ Attr.id "outer" ]
                                        [ Html.div [ Attr.class "inner" ]
                                            [ Html.text "Hello" ]
                                        ]
                                    ]
                                }
                        }
                        |> PagesProgram.withinFind
                            [ PSelector.id "outer" ]
                            (PagesProgram.withinFind
                                [ PSelector.class "inner" ]
                                (PagesProgram.ensureViewHas [ PSelector.text "Hello" ])
                            )
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas text \"Hello\" (within #outer > .inner)"
                            ]
            , test "plain within does not add scope labels" <|
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
                                        [ Html.text "Content" ]
                                    ]
                                }
                        }
                        |> PagesProgram.within
                            (Query.find [ Selector.id "main" ])
                            (PagesProgram.ensureViewHas [ PSelector.text "Content" ])
                        |> PagesProgram.toSnapshots
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas text \"Content\""
                            ]
            , test "assertion snapshots carry selector data for highlighting" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body =
                                    [ Html.div [ Attr.class "greeting", Attr.id "main" ]
                                        [ Html.text "Hello" ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Hello", PSelector.class "greeting" ]
                        |> PagesProgram.ensureViewHas [ PSelector.id "main" ]
                        |> PagesProgram.ensureViewHas [ PSelector.tag "div" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .assertionSelectors
                        |> Expect.equal
                            [ []  -- start has no assertion selectors
                            , [ ByText "Hello", ByClass "greeting" ]
                            , [ ById_ "main" ]
                            , [ ByTag_ "div" ]
                            ]
            , test "ensureViewHasNot stores assertion selectors for highlighting" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body = [ Html.text "Hello" ]
                                }
                        }
                        |> PagesProgram.ensureViewHasNot [ PSelector.text "Goodbye" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .assertionSelectors
                        |> Expect.equal
                            [ []
                            , [ ByText "Goodbye" ]
                            ]
            , test "value selectors stored in assertion snapshots" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body =
                                    [ Html.input [ Attr.value "Buy milk" ] []
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .assertionSelectors
                        |> Expect.equal
                            [ []
                            , [ ByValue "Buy milk" ]
                            ]
            , test "withinFind snapshots carry scope selectors for highlighting" <|
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
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Sections"
                                , body =
                                    [ Html.div [ Attr.id "counter" ]
                                        [ Html.text (String.fromInt model.count) ]
                                    ]
                                }
                        }
                        |> PagesProgram.withinFind
                            [ PSelector.id "counter" ]
                            (PagesProgram.ensureViewHas [ PSelector.text "0" ])
                        |> PagesProgram.toSnapshots
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ []  -- start
                            , [ [ ById_ "counter" ] ]  -- assertion inside withinFind
                            ]
            , test "nested withinFind carries nested scope selectors" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Nested"
                                , body =
                                    [ Html.div [ Attr.id "outer" ]
                                        [ Html.div [ Attr.class "inner" ]
                                            [ Html.text "Hello" ]
                                        ]
                                    ]
                                }
                        }
                        |> PagesProgram.withinFind
                            [ PSelector.id "outer" ]
                            (PagesProgram.withinFind
                                [ PSelector.class "inner" ]
                                (PagesProgram.ensureViewHas [ PSelector.text "Hello" ])
                            )
                        |> PagesProgram.toSnapshots
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ []  -- start
                            , [ [ ById_ "outer" ], [ ByClass "inner" ] ]  -- nested scopes
                            ]
            , test "plain within has empty scope selectors" <|
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
                                        [ Html.text "Content" ]
                                    ]
                                }
                        }
                        |> PagesProgram.within
                            (Query.find [ Selector.id "main" ])
                            (PagesProgram.ensureViewHas [ PSelector.text "Content" ])
                        |> PagesProgram.toSnapshots
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ []  -- start
                            , []  -- plain within = no scope selectors
                            ]
            , test "clickButtonWith inside withinFind carries scope selectors" <|
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
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Scoped Click"
                                , body =
                                    [ Html.div [ Attr.id "section-a" ]
                                        [ Html.button [ Attr.class "action-btn", Html.Events.onClick Increment ] [ Html.text "Do it" ] ]
                                    , Html.div [ Attr.id "section-b" ]
                                        [ Html.button [ Attr.class "action-btn", Html.Events.onClick Decrement ] [ Html.text "Do it" ] ]
                                    ]
                                }
                        }
                        |> PagesProgram.withinFind
                            [ PSelector.id "section-a" ]
                            (PagesProgram.clickButtonWith [ PSelector.class "action-btn" ])
                        |> PagesProgram.toSnapshots
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ []  -- start
                            , [ [ ById_ "section-a" ] ]  -- interaction inside withinFind
                            ]
            , test "non-scoped assertions have empty scope selectors" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Home"
                                , body = [ Html.text "Hello" ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Hello" ]
                        |> PagesProgram.toSnapshots
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ []  -- start
                            , []  -- no scope
                            ]
            ]
        , describe "disabled button detection"
            [ test "clickButton fails on disabled button" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Form"
                                , body =
                                    [ Html.button
                                        [ Attr.disabled True ]
                                        [ Html.text "Submit" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Submit"
                        |> PagesProgram.done
                        |> expectFailContaining "disabled"
            , test "clickButton succeeds on enabled button" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { clicked = False }, [] )
                        , update =
                            \_ model -> ( { model | clicked = True }, [] )
                        , view =
                            \_ model ->
                                { title = "Form"
                                , body =
                                    [ Html.button
                                        [ Attr.disabled False
                                        , Html.Events.onClick ()
                                        ]
                                        [ Html.text "Submit" ]
                                    , if model.clicked then
                                        Html.text "Clicked!"
                                      else
                                        Html.text ""
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Submit"
                        |> PagesProgram.ensureViewHas [ PSelector.text "Clicked!" ]
                        |> PagesProgram.done
            ]
        , describe "ambiguous button detection"
            [ test "clickButton fails when multiple buttons match" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "List"
                                , body =
                                    [ Html.div []
                                        [ Html.button [ Html.Events.onClick () ] [ Html.text "Delete" ]
                                        , Html.button [ Html.Events.onClick () ] [ Html.text "Delete" ]
                                        , Html.button [ Html.Events.onClick () ] [ Html.text "Delete" ]
                                        ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Delete"
                        |> PagesProgram.done
                        |> expectFailContaining "Delete"
            ]
        , describe "Bug fix: pending effects must not be overwritten"
            [ test "done fails when effects are pending after another interaction" <|
                \() ->
                    -- Bug: clicking a button that triggers an effect, then clicking
                    -- another button before resolving, used to silently drop the effect.
                    -- After fix: done should fail because there's still a pending effect.
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { result = Nothing, other = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    QueueFetch ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "value" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotResult
                                          ]
                                        )

                                    DoOtherThing ->
                                        ( { model | other = True }, [] )

                                    GotResult value ->
                                        ( { model | result = Just value }, [] )
                        , view =
                            \_ model ->
                                { title = "Queue Test"
                                , body =
                                    [ Html.button [ Html.Events.onClick QueueFetch ] [ Html.text "Fetch" ]
                                    , Html.button [ Html.Events.onClick DoOtherThing ] [ Html.text "Other" ]
                                    , case model.result of
                                        Just v ->
                                            Html.text ("Result: " ++ v)

                                        Nothing ->
                                            Html.text "No result"
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Fetch"
                        -- Click another button BEFORE resolving the effect
                        |> PagesProgram.clickButton "Other"
                        -- done should fail: the HTTP effect from "Fetch" is still pending
                        |> PagesProgram.done
                        |> expectFailContaining "pending"
            , test "resolveEffect works after another interaction" <|
                \() ->
                    -- The effect from the first click should survive a second click
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { result = Nothing, other = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    QueueFetch ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "value" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotResult
                                          ]
                                        )

                                    DoOtherThing ->
                                        ( { model | other = True }, [] )

                                    GotResult value ->
                                        ( { model | result = Just value }, [] )
                        , view =
                            \_ model ->
                                { title = "Queue Test"
                                , body =
                                    [ Html.button [ Html.Events.onClick QueueFetch ] [ Html.text "Fetch" ]
                                    , Html.button [ Html.Events.onClick DoOtherThing ] [ Html.text "Other" ]
                                    , case model.result of
                                        Just v ->
                                            Html.text ("Result: " ++ v)

                                        Nothing ->
                                            Html.text "No result"
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Fetch"
                        |> PagesProgram.clickButton "Other"
                        -- Should still be able to resolve the effect from "Fetch"
                        |> PagesProgram.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.example.com/data"
                                (Encode.object [ ( "value", Encode.string "hello" ) ])
                            )
                        |> PagesProgram.ensureViewHas [ PSelector.text "Result: hello" ]
                        |> PagesProgram.done
            ]
        , describe "Bug fix: FatalError in data produces clean test failure"
            [ test "done fails cleanly when data BackendTask produces FatalError" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.fail (FatalError.fromString "Database connection failed")
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.done
                        |> expectFailContaining "Database connection failed"
            , test "ensureViewHas fails cleanly when data BackendTask produces FatalError" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.fail (FatalError.fromString "Service unavailable")
                        , init = \_ -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Hello" ]
                        |> PagesProgram.done
                        |> expectFailContaining "Service unavailable"
            ]
        , describe "simulateIncomingPort (elm-program-test style)"
            [ test "can simulate an incoming port message" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { messages = [] }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    GotWebSocket message ->
                                        ( { model | messages = model.messages ++ [ message ] }, [] )
                        , view =
                            \_ model ->
                                { title = "Chat"
                                , body =
                                    [ Html.text
                                        (if List.isEmpty model.messages then
                                            "No messages"

                                         else
                                            String.join ", " model.messages
                                        )
                                    ]
                                }
                        }
                        |> PagesProgram.withSimulatedSubscriptions
                            (\_ ->
                                SimulatedSub.port_ "websocketReceived"
                                    (Decode.string |> Decode.map GotWebSocket)
                            )
                        |> PagesProgram.ensureViewHas [ PSelector.text "No messages" ]
                        |> PagesProgram.simulateIncomingPort "websocketReceived"
                            (Encode.string "hello")
                        |> PagesProgram.ensureViewHas [ PSelector.text "hello" ]
                        |> PagesProgram.simulateIncomingPort "websocketReceived"
                            (Encode.string "world")
                        |> PagesProgram.ensureViewHas [ PSelector.text "hello, world" ]
                        |> PagesProgram.done
            , test "simulateIncomingPort fails when not subscribed to port" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.withSimulatedSubscriptions
                            (\_ -> SimulatedSub.none)
                        |> PagesProgram.simulateIncomingPort "somePort"
                            (Encode.string "data")
                        |> PagesProgram.done
                        |> expectFailContaining "not currently subscribed"
            , test "simulateIncomingPort fails without withSimulatedSubscriptions" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.simulateIncomingPort "somePort"
                            (Encode.string "data")
                        |> PagesProgram.done
                        |> expectFailContaining "withSimulatedSubscriptions"
            , test "subscriptions are model-dependent" <|
                \() ->
                    -- The subscription function re-evaluates with the current
                    -- model. When listening is False, port is not subscribed.
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { listening = False, lastMessage = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    StartListening ->
                                        ( { model | listening = True }, [] )

                                    ReceivedData value ->
                                        ( { model | lastMessage = Just value }, [] )
                        , view =
                            \_ model ->
                                { title = "Listener"
                                , body =
                                    [ if model.listening then
                                        Html.text "Listening"

                                      else
                                        Html.button [ Html.Events.onClick StartListening ]
                                            [ Html.text "Start" ]
                                    , case model.lastMessage of
                                        Just msg ->
                                            Html.text ("Got: " ++ msg)

                                        Nothing ->
                                            Html.text ""
                                    ]
                                }
                        }
                        |> PagesProgram.withSimulatedSubscriptions
                            (\model ->
                                if model.listening then
                                    SimulatedSub.port_ "dataPort"
                                        (Decode.string |> Decode.map ReceivedData)

                                else
                                    SimulatedSub.none
                            )
                        -- Not listening yet, so port should not be subscribed
                        |> PagesProgram.simulateIncomingPort "dataPort"
                            (Encode.string "too early")
                        |> PagesProgram.done
                        |> expectFailContaining "not currently subscribed"
            ]
        , describe "simulateHttpError"
            [ test "simulates a network error on data loading" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/data"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \value -> ( { value = value }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Data", body = [ Html.text model.value ] }
                        }
                        |> PagesProgram.simulateHttpError "GET"
                            "https://api.example.com/data"
                            NetworkError
                        |> PagesProgram.done
                        |> expectFailContaining "NetworkError"
            , test "simulates a timeout on data loading" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/data"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \value -> ( { value = value }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Data", body = [ Html.text model.value ] }
                        }
                        |> PagesProgram.simulateHttpError "GET"
                            "https://api.example.com/data"
                            Timeout
                        |> PagesProgram.done
                        |> expectFailContaining "Timeout"
            ]
        , describe "HTTP simulation error messages"
            [ test "simulateHttpPost with no pending requests shows the URL you tried" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed "ready"
                        , init = \msg -> ( { text = msg }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Test", body = [ Html.text model.text ] }
                        }
                        |> PagesProgram.simulateHttpPost
                            "https://api.example.com/data"
                            (Encode.object [])
                        |> PagesProgram.done
                        |> expectFailContaining "api.example.com/data"
            , test "simulateHttpGet with no pending requests shows the URL you tried" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed "ready"
                        , init = \msg -> ( { text = msg }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "Test", body = [ Html.text model.text ] }
                        }
                        |> PagesProgram.simulateHttpGet
                            "https://api.example.com/users"
                            (Encode.object [])
                        |> PagesProgram.done
                        |> expectFailContaining "api.example.com/users"
            , test "simulateHttpPost with wrong URL shows both the attempted URL and the pending request" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/actual-endpoint"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \name -> ( { name = name }, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                        }
                        |> PagesProgram.simulateHttpPost
                            "https://api.example.com/wrong-endpoint"
                            (Encode.object [])
                        |> PagesProgram.done
                        |> Expect.all
                            [ expectFailContaining "wrong-endpoint"
                            , expectFailContaining "actual-endpoint"
                            ]
            ]
        , describe "selectOption"
            [ test "selecting a dropdown option updates the view" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { color = "red" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    SelectColor c ->
                                        ( { model | color = c }, [] )
                        , view =
                            \_ model ->
                                { title = "Colors"
                                , body =
                                    [ Html.label [ Attr.for "color-select" ] [ Html.text "Favorite Color" ]
                                    , Html.select
                                        [ Attr.id "color-select"
                                        , Html.Events.onInput SelectColor
                                        ]
                                        [ Html.option [ Attr.value "red" ] [ Html.text "Red" ]
                                        , Html.option [ Attr.value "blue" ] [ Html.text "Blue" ]
                                        , Html.option [ Attr.value "green" ] [ Html.text "Green" ]
                                        ]
                                    , Html.text ("Selected: " ++ model.color)
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Selected: red" ]
                        |> PagesProgram.selectOption "color-select" "Favorite Color" "blue" "Blue"
                        |> PagesProgram.ensureViewHas [ PSelector.text "Selected: blue" ]
                        |> PagesProgram.done
            , test "selectOption fails when select element not found" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "No selects" ] }
                        }
                        |> PagesProgram.selectOption "missing" "Missing" "val" "text"
                        |> PagesProgram.done
                        |> expectFailContaining "selectOption"
            , test "selectOption fails when the associated label does not match" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { color = "red" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    SelectColor c ->
                                        ( { model | color = c }, [] )
                        , view =
                            \_ model ->
                                { title = "Colors"
                                , body =
                                    [ Html.label [ Attr.for "color-select" ] [ Html.text "Favorite Color" ]
                                    , Html.select
                                        [ Attr.id "color-select"
                                        , Html.Events.onInput SelectColor
                                        ]
                                        [ Html.option [ Attr.value "red" ] [ Html.text "Red" ]
                                        , Html.option [ Attr.value "blue" ] [ Html.text "Blue" ]
                                        ]
                                    , Html.text ("Selected: " ++ model.color)
                                    ]
                                }
                        }
                        |> PagesProgram.selectOption "color-select" "Wrong Label" "blue" "Blue"
                        |> PagesProgram.done
                        |> expectFailContaining "Wrong Label"
            , test "selectOption fails when the option text/value pair does not exist" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { color = "red" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    SelectColor c ->
                                        ( { model | color = c }, [] )
                        , view =
                            \_ model ->
                                { title = "Colors"
                                , body =
                                    [ Html.label [ Attr.for "color-select" ] [ Html.text "Favorite Color" ]
                                    , Html.select
                                        [ Attr.id "color-select"
                                        , Html.Events.onInput SelectColor
                                        ]
                                        [ Html.option [ Attr.value "red" ] [ Html.text "Red" ]
                                        , Html.option [ Attr.value "blue" ] [ Html.text "Blue" ]
                                        ]
                                    , Html.text ("Selected: " ++ model.color)
                                    ]
                                }
                        }
                        |> PagesProgram.selectOption "color-select" "Favorite Color" "blue" "Not Blue"
                        |> PagesProgram.done
                        |> expectFailContaining "Not Blue"
            ]
        , describe "expectViewHas (terminal assertion)"
            [ test "passes when view has selector" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.expectViewHas [ PSelector.text "Hello" ]
            , test "fails when view does not have selector" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.expectViewHas [ PSelector.text "Goodbye" ]
                        |> expectFailContaining "Goodbye"
            ]
        , describe "cookie jar"
            [ test "CookieJar.empty has no cookies" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.get "anything"
                        |> Expect.equal Nothing
            , test "CookieJar.set adds a cookie" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.set "theme" "dark"
                        |> CookieJar.get "theme"
                        |> Expect.equal (Just "dark")
            , test "CookieJar.fromSetCookieHeaders parses Set-Cookie headers" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.applySetCookieHeaders
                            [ "session=abc123; Path=/; HttpOnly"
                            , "theme=dark; Path=/"
                            ]
                        |> CookieJar.get "session"
                        |> Expect.equal (Just "abc123")
            , test "CookieJar.toCookieDict produces dict for request" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.set "a" "1"
                        |> CookieJar.set "b" "2"
                        |> CookieJar.toDict
                        |> Dict.get "a"
                        |> Expect.equal (Just "1")
            , test "Set-Cookie with multiple attributes parsed correctly" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.applySetCookieHeaders
                            [ "token=xyz789; Path=/; Domain=.example.com; Secure; HttpOnly; SameSite=Strict; Max-Age=3600" ]
                        |> CookieJar.get "token"
                        |> Expect.equal (Just "xyz789")
            , test "multiple Set-Cookie headers accumulate" <|
                \() ->
                    let
                        jar =
                            CookieJar.empty
                                |> CookieJar.applySetCookieHeaders
                                    [ "a=1; Path=/"
                                    , "b=2; Path=/"
                                    , "c=3; Path=/"
                                    ]
                    in
                    ( CookieJar.get "a" jar
                    , CookieJar.get "b" jar
                    , CookieJar.get "c" jar
                    )
                        |> Expect.equal ( Just "1", Just "2", Just "3" )
            , test "Set-Cookie overwrites existing cookie" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.set "theme" "light"
                        |> CookieJar.applySetCookieHeaders
                            [ "theme=dark; Path=/" ]
                        |> CookieJar.get "theme"
                        |> Expect.equal (Just "dark")
            , test "URL-encoded cookie values are decoded" <|
                \() ->
                    CookieJar.empty
                        |> CookieJar.applySetCookieHeaders
                            [ "data=hello%20world; Path=/" ]
                        |> CookieJar.get "data"
                        |> Expect.equal (Just "hello world")
            ]
        , describe "startWithEffects (custom Effect type simulation)"
            [ test "user-defined effects are converted to BackendTasks" <|
                \() ->
                    -- Users have a custom Effect type. They provide a function
                    -- to convert it to BackendTasks the framework can handle.
                    PagesProgram.startWithEffects
                        (\effect ->
                            case effect of
                                MyEffectNone ->
                                    []

                                MyEffectBatch effects ->
                                    List.concatMap
                                        (\e ->
                                            case e of
                                                MyFetchApi toMsg ->
                                                    [ BackendTask.Http.getJson
                                                        "https://api.example.com/data"
                                                        (Decode.field "name" Decode.string)
                                                        |> BackendTask.allowFatal
                                                        |> BackendTask.map toMsg
                                                    ]

                                                _ ->
                                                    []
                                        )
                                        effects

                                MyFetchApi toMsg ->
                                    [ BackendTask.Http.getJson
                                        "https://api.example.com/data"
                                        (Decode.field "name" Decode.string)
                                        |> BackendTask.allowFatal
                                        |> BackendTask.map toMsg
                                    ]
                        )
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { name = Nothing }, MyEffectNone )
                        , update =
                            \msg model ->
                                case msg of
                                    LoadName ->
                                        ( model, MyFetchApi GotName )

                                    GotName n ->
                                        ( { model | name = Just n }, MyEffectNone )
                        , view =
                            \_ model ->
                                { title = "Custom Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick LoadName ] [ Html.text "Load" ]
                                    , case model.name of
                                        Just n ->
                                            Html.text ("Name: " ++ n)

                                        Nothing ->
                                            Html.text "No name"
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "No name" ]
                        |> PagesProgram.clickButton "Load"
                        |> PagesProgram.resolveEffect
                            (BackendTaskTest.simulateHttpGet
                                "https://api.example.com/data"
                                (Encode.object [ ( "name", Encode.string "Alice" ) ])
                            )
                        |> PagesProgram.ensureViewHas [ PSelector.text "Name: Alice" ]
                        |> PagesProgram.done
            ]
        , describe "effect tracking"
            [ test "done reports count of unresolved effects" <|
                \() ->
                    -- When there are pending effects at the end, done should
                    -- report how many AND describe what's pending
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { value = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    TriggerEffect ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "v" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotEffectResult
                                          ]
                                        )

                                    GotEffectResult v ->
                                        ( { model | value = Just v }, [] )
                        , view =
                            \_ model ->
                                { title = "Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ]
                                    , case model.value of
                                        Just v ->
                                            Html.text ("Got: " ++ v)

                                        Nothing ->
                                            Html.text "Waiting"
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.done
                        |> expectFailContaining "1 pending"
            , test "multiple effects from different interactions all tracked" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { value = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    TriggerEffect ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "v" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotEffectResult
                                          ]
                                        )

                                    GotEffectResult v ->
                                        ( { model | value = Just v }, [] )
                        , view =
                            \_ model ->
                                { title = "Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.done
                        |> expectFailContaining "2 pending"
            , test "done describes what effects are pending" <|
                \() ->
                    -- done should include the URLs of pending HTTP requests
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { value = Nothing }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    TriggerEffect ->
                                        ( model
                                        , [ BackendTask.Http.getJson
                                                "https://api.example.com/data"
                                                (Decode.field "v" Decode.string)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.map GotEffectResult
                                          ]
                                        )

                                    GotEffectResult v ->
                                        ( { model | value = Just v }, [] )
                        , view =
                            \_ model ->
                                { title = "Effect"
                                , body =
                                    [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ] ]
                                }
                        }
                        |> PagesProgram.clickButton "Go"
                        |> PagesProgram.done
                        |> expectFailContaining "api.example.com"
            ]
        , describe "expectModel"
            [ test "can inspect the model directly" <|
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
                                    [ Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    , Html.text (String.fromInt model.count)
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.expectModel
                            (\model -> model.count |> Expect.equal 3)
            , test "expectModel fails with useful message" <|
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
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    , Html.text (String.fromInt model.count)
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.expectModel
                            (\model -> model.count |> Expect.equal 99)
                        |> expectFailContaining "Expect.equal"
            ]
        , describe "withModelToString"
            [ test "annotates the latest snapshot when enabled mid-test without rewriting history" <|
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
                                        ( model, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.button [ Html.Events.onClick Increment ] [ Html.text "+1" ]
                                    , Html.text (String.fromInt model.count)
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.withModelToString (\model -> "count=" ++ String.fromInt model.count)
                        |> PagesProgram.clickButton "+1"
                        |> PagesProgram.toSnapshots
                        |> List.map .modelState
                        |> Expect.equal
                            [ Nothing
                            , Just "count=1"
                            , Just "count=2"
                            ]
            ]
        , describe "within (DOM scoping)"
            [ test "scopes clickButton to a specific element" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { a = 0, b = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    IncrA ->
                                        ( { model | a = model.a + 1 }, [] )

                                    IncrB ->
                                        ( { model | b = model.b + 1 }, [] )
                        , view =
                            \_ model ->
                                { title = "Scoped"
                                , body =
                                    [ Html.div [ Attr.id "section-a" ]
                                        [ Html.text ("A: " ++ String.fromInt model.a)
                                        , Html.button [ Html.Events.onClick IncrA ] [ Html.text "+1" ]
                                        ]
                                    , Html.div [ Attr.id "section-b" ]
                                        [ Html.text ("B: " ++ String.fromInt model.b)
                                        , Html.button [ Html.Events.onClick IncrB ] [ Html.text "+1" ]
                                        ]
                                    ]
                                }
                        }
                        |> PagesProgram.within
                            (Query.find [ Selector.id "section-b" ])
                            (PagesProgram.clickButton "+1")
                        |> PagesProgram.expectModel
                            (\model ->
                                Expect.equal { a = 0, b = 1 } { a = model.a, b = model.b }
                            )
            , test "within resets scope after block" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { a = 0, b = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    IncrA ->
                                        ( { model | a = model.a + 1 }, [] )

                                    IncrB ->
                                        ( { model | b = model.b + 1 }, [] )
                        , view =
                            \_ model ->
                                { title = "Scoped"
                                , body =
                                    [ Html.div [ Attr.id "section-a" ]
                                        [ Html.text ("A: " ++ String.fromInt model.a)
                                        , Html.button [ Html.Events.onClick IncrA ] [ Html.text "+1" ]
                                        ]
                                    , Html.div [ Attr.id "section-b" ]
                                        [ Html.text ("B: " ++ String.fromInt model.b)
                                        , Html.button [ Html.Events.onClick IncrB ] [ Html.text "+1" ]
                                        ]
                                    ]
                                }
                        }
                        -- Click in section-b
                        |> PagesProgram.within
                            (Query.find [ Selector.id "section-b" ])
                            (PagesProgram.clickButton "+1")
                        -- After within, scope resets to full view.
                        -- Use within again to target section-a specifically.
                        |> PagesProgram.within
                            (Query.find [ Selector.id "section-a" ])
                            (PagesProgram.clickButton "+1")
                        |> PagesProgram.expectModel
                            (\model ->
                                Expect.equal { a = 1, b = 1 } { a = model.a, b = model.b }
                            )
            ]
        , describe "fillInTextarea"
            [ test "fills in a textarea by finding the first one" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { content = "" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    UpdateContent c ->
                                        ( { model | content = c }, [] )
                        , view =
                            \_ model ->
                                { title = "Editor"
                                , body =
                                    [ Html.textarea
                                        [ Attr.value model.content
                                        , Html.Events.onInput UpdateContent
                                        ]
                                        []
                                    , Html.text ("Content: " ++ model.content)
                                    ]
                                }
                        }
                        |> PagesProgram.fillInTextarea "Hello from textarea!"
                        |> PagesProgram.ensureViewHas [ PSelector.text "Content: Hello from textarea!" ]
                        |> PagesProgram.done
            ]
        , describe "expectView (terminal)"
            [ test "passes with custom query assertion" <|
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
                                        [ Html.h1 [] [ Html.text "Welcome" ] ]
                                    ]
                                }
                        }
                        |> PagesProgram.expectView
                            (Query.find [ Selector.id "main" ]
                                >> Query.has [ Selector.tag "h1" ]
                            )
            , test "fails with useful message" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.expectView
                            (Query.has [ Selector.id "nonexistent" ])
                        |> expectFailContaining "id"
            ]
        , describe "simulateDomEvent"
            [ test "simulates a custom event on a targeted element" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { focused = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    GotFocus ->
                                        ( { model | focused = True }, [] )
                        , view =
                            \_ model ->
                                { title = "Focus"
                                , body =
                                    [ Html.input
                                        [ Attr.id "my-input"
                                        , Html.Events.onFocus GotFocus
                                        ]
                                        []
                                    , if model.focused then
                                        Html.text "Focused!"

                                      else
                                        Html.text "Not focused"
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Not focused" ]
                        |> PagesProgram.simulateDomEvent
                            (Query.find [ Selector.id "my-input" ])
                            Event.focus
                        |> PagesProgram.ensureViewHas [ PSelector.text "Focused!" ]
                        |> PagesProgram.done
            ]
        , describe "clickLink"
            [ test "clickLink fails when link text not found" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view =
                            \_ _ ->
                                { title = "Page"
                                , body = [ Html.text "No links here" ]
                                }
                        }
                        |> PagesProgram.clickLink "Go somewhere" "/somewhere"
                        |> PagesProgram.done
                        |> expectFailContaining "clickLink"
            , test "clickLink fails when the href does not match the rendered link" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { page = "home" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Navigate url ->
                                        ( { model | page = url }, [] )
                        , view =
                            \_ model ->
                                { title = "Nav"
                                , body =
                                    [ Html.a
                                        [ Attr.href "/team"
                                        , Html.Events.onClick (Navigate "/team")
                                        ]
                                        [ Html.text "About" ]
                                    , Html.text ("Page: " ++ model.page)
                                    ]
                                }
                        }
                        |> PagesProgram.clickLink "About" "/about"
                        |> PagesProgram.done
                        |> expectFailContaining "no link with href"
            , test "clickLink fails instead of silently succeeding when the link cannot navigate" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { page = "home" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Navigate url ->
                                        ( { model | page = url }, [] )
                        , view =
                            \_ model ->
                                { title = "Nav"
                                , body =
                                    [ Html.a
                                        [ Attr.href "/about" ]
                                        [ Html.text "About" ]
                                    , Html.text ("Page: " ++ model.page)
                                    ]
                                }
                        }
                        |> PagesProgram.clickLink "About" "/about"
                        |> PagesProgram.done
                        |> expectFailContaining "no navigation handler or click handler found"
            , test "clickLink finds link by text and simulates click" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { page = "home" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    Navigate url ->
                                        ( { model | page = url }, [] )
                        , view =
                            \_ model ->
                                { title = "Nav"
                                , body =
                                    [ Html.a
                                        [ Attr.href "/about"
                                        , Html.Events.onClick (Navigate "/about")
                                        ]
                                        [ Html.text "About" ]
                                    , Html.text ("Page: " ++ model.page)
                                    ]
                                }
                        }
                        |> PagesProgram.clickLink "About" "/about"
                        |> PagesProgram.ensureViewHas [ PSelector.text "Page: /about" ]
                        |> PagesProgram.done
            ]
        , describe "navigateTo"
            [ test "navigateTo fails without startPlatform" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.navigateTo "/about"
                        |> PagesProgram.done
                        |> expectFailContaining "Navigation is only supported"
            , test "navigateTo fails while data is resolving" <|
                \() ->
                    PagesProgram.start
                        { data =
                            BackendTask.Http.getJson
                                "https://api.example.com/data"
                                Decode.string
                                |> BackendTask.allowFatal
                        , init = \_ -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.navigateTo "/about"
                        |> PagesProgram.done
                        |> expectFailContaining "resolving"
            ]
        , describe "ensureBrowserUrl"
            [ test "ensureBrowserUrl fails without startPlatform" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.ensureBrowserUrl
                            (\url -> url |> Expect.equal "anything")
                        |> PagesProgram.done
                        |> expectFailContaining "URL tracking is only supported"
            ]
        , describe "fillInTextarea errors"
            [ test "fillInTextarea fails when no textarea found" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "No textarea" ] }
                        }
                        |> PagesProgram.fillInTextarea "some text"
                        |> PagesProgram.done
                        |> expectFailContaining "fillInTextarea"
            ]
        , describe "simulateDomEvent errors"
            [ test "simulateDomEvent fails when element not found" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.simulateDomEvent
                            (Query.find [ Selector.id "missing" ])
                            Event.focus
                        |> PagesProgram.done
                        |> expectFailContaining "simulateDomEvent"
            ]
        , describe "selectOption errors"
            [ test "selectOption fails when select not found" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "No select" ] }
                        }
                        |> PagesProgram.selectOption "missing" "Label" "val" "text"
                        |> PagesProgram.done
                        |> expectFailContaining "selectOption"
            ]
        , describe "CookieJar edge cases"
            [ test "malformed Set-Cookie without name=value is ignored" <|
                \() ->
                    -- "Path=/; HttpOnly" is not a valid cookie, just attributes
                    CookieJar.empty
                        |> CookieJar.applySetCookieHeaders
                            [ "Path=/; HttpOnly" ]
                        |> CookieJar.get "Path"
                        |> Expect.equal Nothing
            ]
        , describe "within error handling"
            [ test "within gives clear error when scope element doesn't exist" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.within
                            (Query.find [ Selector.id "nonexistent" ])
                            (PagesProgram.ensureViewHas [ PSelector.text "anything" ])
                        |> PagesProgram.done
                        |> expectFailContaining "nonexistent"
            ]
        , describe "textarea support (legacy)"
            [ test "fillIn works with textarea" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { content = "" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    UpdateContent c ->
                                        ( { model | content = c }, [] )
                        , view =
                            \_ model ->
                                { title = "Editor"
                                , body =
                                    [ Html.textarea
                                        [ Attr.id "editor"
                                        , Attr.value model.content
                                        , Html.Events.onInput UpdateContent
                                        ]
                                        []
                                    , Html.text ("Content: " ++ model.content)
                                    ]
                                }
                        }
                        |> PagesProgram.fillIn "editor" "editor" "Hello textarea!"
                        |> PagesProgram.ensureViewHas [ PSelector.text "Content: Hello textarea!" ]
                        |> PagesProgram.done
            ]
        , describe "SimulatedEffect (Effect.testPerform integration)"
            [ test "simulateMsg dispatches a message through update" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { count = 0 }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    SimIncrement ->
                                        ( { model | count = model.count + 1 }, [] )

                                    SimReset ->
                                        ( { model | count = 0 }, [] )
                        , view =
                            \_ model ->
                                { title = "Counter"
                                , body =
                                    [ Html.text ("Count: " ++ String.fromInt model.count)
                                    , Html.button [ Html.Events.onClick SimIncrement ] [ Html.text "+" ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                        |> PagesProgram.simulateMsg SimIncrement
                        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                        |> PagesProgram.simulateMsg SimIncrement
                        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
                        |> PagesProgram.simulateMsg SimReset
                        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                        |> PagesProgram.done
            , test "simulateMsg chains through update effects" <|
                \() ->
                    -- When update returns an effect that should dispatch another msg,
                    -- the user uses simulateMsg to inject it (the start path equivalent
                    -- of SimulatedEffect.DispatchMsg in startPlatform)
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { items = [], status = "idle" }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    SimLoadItems ->
                                        ( { model | status = "loading" }, [] )

                                    SimItemsLoaded items ->
                                        ( { model | items = items, status = "loaded" }, [] )
                        , view =
                            \_ model ->
                                { title = "Items"
                                , body =
                                    [ Html.text ("Status: " ++ model.status)
                                    , Html.ul []
                                        (List.map (\item -> Html.li [] [ Html.text item ]) model.items)
                                    , Html.button [ Html.Events.onClick SimLoadItems ] [ Html.text "Load" ]
                                    ]
                                }
                        }
                        |> PagesProgram.clickButton "Load"
                        |> PagesProgram.ensureViewHas [ PSelector.text "Status: loading" ]
                        |> PagesProgram.simulateMsg (SimItemsLoaded [ "Apple", "Banana" ])
                        |> PagesProgram.ensureViewHas [ PSelector.text "Status: loaded" ]
                        |> PagesProgram.ensureViewHas [ PSelector.text "Apple" ]
                        |> PagesProgram.ensureViewHas [ PSelector.text "Banana" ]
                        |> PagesProgram.done
            , test "startWithEffects with SimulatedEffect-style decomposition" <|
                \() ->
                    -- The startWithEffects path converts custom effects to BackendTasks.
                    -- When an effect is pure (no HTTP needed), use BackendTask.succeed
                    -- to dispatch the message immediately via resolveEffect.
                    PagesProgram.startWithEffects
                        (\effect ->
                            case effect of
                                SimEffectNone ->
                                    []

                                SimEffectSendMsg msg ->
                                    [ BackendTask.succeed msg
                                        |> BackendTask.allowFatal
                                    ]

                                SimEffectBatch effects ->
                                    List.concatMap
                                        (\e ->
                                            case e of
                                                SimEffectSendMsg msg ->
                                                    [ BackendTask.succeed msg |> BackendTask.allowFatal ]

                                                _ ->
                                                    []
                                        )
                                        effects
                        )
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { message = "initial" }, SimEffectNone )
                        , update =
                            \msg model ->
                                case msg of
                                    SimSetMessage s ->
                                        ( { model | message = s }, SimEffectNone )

                                    SimTriggerChain ->
                                        ( model, SimEffectSendMsg (SimSetMessage "chained!") )
                        , view =
                            \_ model ->
                                { title = "Effect Chain"
                                , body =
                                    [ Html.text ("Message: " ++ model.message)
                                    , Html.button [ Html.Events.onClick SimTriggerChain ] [ Html.text "Chain" ]
                                    ]
                                }
                        }
                        |> PagesProgram.ensureViewHas [ PSelector.text "Message: initial" ]
                        |> PagesProgram.clickButton "Chain"
                        |> PagesProgram.resolveEffect identity
                        |> PagesProgram.ensureViewHas [ PSelector.text "Message: chained!" ]
                        |> PagesProgram.done
            , test "SimulatedEffect.map preserves message transformation" <|
                \() ->
                    -- Verify that SimulatedEffect.map correctly transforms messages
                    let
                        original =
                            SimulatedEffect.dispatchMsg 42

                        mapped =
                            SimulatedEffect.map (\n -> String.fromInt n) original
                    in
                    case mapped of
                        SimulatedEffect.DispatchMsg s ->
                            s |> Expect.equal "42"

                        _ ->
                            Expect.fail "Expected DispatchMsg after map"
            , test "SimulatedEffect.map over Batch transforms all messages" <|
                \() ->
                    let
                        original =
                            SimulatedEffect.batch
                                [ SimulatedEffect.dispatchMsg 1
                                , SimulatedEffect.none
                                , SimulatedEffect.dispatchMsg 2
                                ]

                        mapped =
                            SimulatedEffect.map (\n -> n * 10) original
                    in
                    case mapped of
                        SimulatedEffect.Batch [ SimulatedEffect.DispatchMsg a, SimulatedEffect.None, SimulatedEffect.DispatchMsg b ] ->
                            Expect.all
                                [ \_ -> a |> Expect.equal 10
                                , \_ -> b |> Expect.equal 20
                                ]
                                ()

                        _ ->
                            Expect.fail "Expected Batch with mapped DispatchMsg values"
            , test "SimulatedEffect.map preserves None" <|
                \() ->
                    let
                        mapped =
                            SimulatedEffect.map identity SimulatedEffect.none
                    in
                    case mapped of
                        SimulatedEffect.None ->
                            Expect.pass

                        _ ->
                            Expect.fail "Expected None to be preserved"
            ]
        , describe "expectBrowserUrl (terminal)"
            [ test "expectBrowserUrl fails without startPlatform" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.expectBrowserUrl
                            (\url -> url |> Expect.equal "anything")
                        |> expectFailContaining "URL tracking is only supported"
            ]
        , describe "ensureBrowserHistory / expectBrowserHistory"
            [ test "ensureBrowserHistory fails without startPlatform" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.ensureBrowserHistory
                            (\history -> Expect.equal [] history)
                        |> PagesProgram.done
                        |> expectFailContaining "only supported with startPlatform"
            , test "expectBrowserHistory fails without startPlatform" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( {}, [] )
                        , update = \_ model -> ( model, [] )
                        , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                        }
                        |> PagesProgram.expectBrowserHistory
                            (\history -> Expect.equal [] history)
                        |> expectFailContaining "only supported with startPlatform"
            ]
        , describe "check with label"
            [ test "check verifies label is associated with the checkbox" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { agreed = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    ToggleAgreed checked ->
                                        ( { model | agreed = checked }, [] )
                        , view =
                            \_ model ->
                                { title = "Form"
                                , body =
                                    [ Html.label [ Attr.for "agree" ] [ Html.text "I agree to the terms" ]
                                    , Html.input
                                        [ Attr.id "agree"
                                        , Attr.type_ "checkbox"
                                        , Attr.checked model.agreed
                                        , Html.Events.onCheck ToggleAgreed
                                        ]
                                        []
                                    , if model.agreed then
                                        Html.text "Terms accepted"

                                      else
                                        Html.text "Please accept terms"
                                    ]
                                }
                        }
                        |> PagesProgram.check "agree" "I agree to the terms" True
                        |> PagesProgram.ensureViewHas [ PSelector.text "Terms accepted" ]
                        |> PagesProgram.done
            , test "check fails when label doesn't match" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { agreed = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    ToggleAgreed checked ->
                                        ( { model | agreed = checked }, [] )
                        , view =
                            \_ model ->
                                { title = "Form"
                                , body =
                                    [ Html.label [ Attr.for "agree" ] [ Html.text "I agree" ]
                                    , Html.input
                                        [ Attr.id "agree"
                                        , Attr.type_ "checkbox"
                                        , Attr.checked model.agreed
                                        , Html.Events.onCheck ToggleAgreed
                                        ]
                                        []
                                    ]
                                }
                        }
                        |> PagesProgram.check "agree" "Wrong label text" True
                        |> PagesProgram.done
                        |> expectFailContaining "Could not find label"
            , test "check works with label wrapping the input" <|
                \() ->
                    PagesProgram.start
                        { data = BackendTask.succeed ()
                        , init = \() -> ( { agreed = False }, [] )
                        , update =
                            \msg model ->
                                case msg of
                                    ToggleAgreed checked ->
                                        ( { model | agreed = checked }, [] )
                        , view =
                            \_ model ->
                                { title = "Form"
                                , body =
                                    [ Html.label []
                                        [ Html.input
                                            [ Attr.id "agree"
                                            , Attr.type_ "checkbox"
                                            , Attr.checked model.agreed
                                            , Html.Events.onCheck ToggleAgreed
                                            ]
                                            []
                                        , Html.text "Accept terms"
                                        ]
                                    , if model.agreed then
                                        Html.text "Terms accepted"

                                      else
                                        Html.text "Please accept terms"
                                    ]
                                }
                        }
                        |> PagesProgram.check "agree" "Accept terms" True
                        |> PagesProgram.ensureViewHas [ PSelector.text "Terms accepted" ]
                        |> PagesProgram.done
            ]
        , describe "SimulatedEffect.OpaqueCmd removed"
            [ test "Cmd maps to None in testPerform (no OpaqueCmd)" <|
                \() ->
                    -- OpaqueCmd was removed; users should map Cmd _ to SimulatedEffect.none
                    -- to be explicit about what is dropped
                    case SimulatedEffect.none of
                        SimulatedEffect.None ->
                            Expect.pass

                        _ ->
                            Expect.fail "Expected None"
            ]
        ]


type SimCounterMsg
    = SimIncrement
    | SimReset


type SimItemsMsg
    = SimLoadItems
    | SimItemsLoaded (List String)


type SimEffect msg
    = SimEffectNone
    | SimEffectSendMsg msg
    | SimEffectBatch (List (SimEffect msg))


type SimChainMsg
    = SimSetMessage String
    | SimTriggerChain


type ContentMsg
    = UpdateContent String


type CounterMsg
    = Increment
    | Decrement


type SearchMsg
    = UpdateQuery String


type CheckMsg
    = ToggleAgreed Bool


type StarsMsg
    = FetchStars
    | GotStars Int


type QueueMsg
    = QueueFetch
    | DoOtherThing
    | GotResult String


type WebSocketMsg
    = GotWebSocket String


type ListenerMsg
    = StartListening
    | ReceivedData String


type SelectMsg
    = SelectColor String


type ScopedMsg
    = IncrA
    | IncrB


type FocusMsg
    = GotFocus


type NavMsg
    = Navigate String


type EffectTrackMsg
    = TriggerEffect
    | GotEffectResult String


type MyEffect msg
    = MyEffectNone
    | MyEffectBatch (List (MyEffect msg))
    | MyFetchApi (String -> msg)


type CustomEffectMsg
    = LoadName
    | GotName String




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
