module PagesProgramTest exposing (all)

import BackendTask
import BackendTask.Custom
import BackendTask.Http
import Bytes.Decode
import Dict
import Expect exposing (Expectation)
import FatalError
import Form
import Html
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Fetcher
import Pages.Internal.Platform as Platform
import Test exposing (Test, describe, test)
import Test.BackendTask exposing (HttpError(..))
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as PSelector
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.CookieJar as CookieJar
import Test.PagesProgram.Internal as PagesProgramInternal exposing (AssertionSelector(..), NetworkStatus(..))
import Test.PagesProgram.SimulatedEffect as SimulatedEffect
import Test.PagesProgram.SimulatedSub as SimulatedSub
import Test.Runner


all : Test
all =
    describe "Test.PagesProgram"
        [ describe "Step 1: static page rendering"
            [ test "renders a page with auto-resolved data" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed "Hello, World!"
                            , init = \greeting -> ( { greeting = greeting }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Home", body = [ Html.text model.greeting ] }
                            }
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Hello, World!" ]
                        ]
            , test "renders a page with unit data" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Static content" ] }
                            }
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Static content" ]
                        ]
            , test "can assert on HTML structure" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.id "main" ]
                        , PagesProgram.ensureViewHas [ PSelector.tag "h1", PSelector.text "Welcome" ]
                        , PagesProgram.ensureViewHas [ PSelector.class "intro" ]
                        , PagesProgram.ensureViewHasNot [ PSelector.text "Error" ]
                        ]
            , test "data value flows through init into model and view" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Alice (Admin)" ]
                        ]
            ]
        , describe "Step 2: data BackendTask with HTTP simulation"
            [ test "resolves data with simulated HTTP GET" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    (Decode.field "name" Decode.string)
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.simulateHttpGet
                            "https://api.example.com/user"
                            (Encode.object [ ( "name", Encode.string "Alice" ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Alice" ]
                        ]
            , test "resolves multiple sequential HTTP POST requests with different bodies to the same URL" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.simulateHttpPost
                            "https://api.example.com/graphql"
                            (Encode.object [ ( "data", Encode.object [ ( "users", Encode.list identity [ Encode.object [ ( "name", Encode.string "Alice" ) ] ] ) ] ) ])
                        , PagesProgram.simulateHttpPost
                            "https://api.example.com/graphql"
                            (Encode.object [ ( "data", Encode.object [ ( "items", Encode.list identity [ Encode.object [ ( "title", Encode.string "Widget" ) ] ] ) ] ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Alice & Widget" ]
                        ]
            , test "done fails when data BackendTask is unresolved" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        []
                        |> expectFailContaining "still resolving"
            , test "ensureViewHas fails with helpful message when data not resolved" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Alice" ]
                        ]
                        |> expectFailContaining "Cannot check view"
            , test "expectView error during resolving lists the pending URL" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.ensureView (\_ -> Expect.pass)
                        ]
                        |> expectFailContaining "https://api.example.com/user"
            ]
        , describe "Step 3: user interaction"
            [ test "clicking a button updates the view" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "0" ]
                        , PagesProgram.clickButton "+1"
                        , PagesProgram.ensureViewHas [ PSelector.text "1" ]
                        , PagesProgram.clickButton "+1"
                        , PagesProgram.clickButton "+1"
                        , PagesProgram.ensureViewHas [ PSelector.text "3" ]
                        , PagesProgram.clickButton "-1"
                        , PagesProgram.ensureViewHas [ PSelector.text "2" ]
                        ]
            , test "clickButton fails with helpful message for missing button" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Home"
                                    , body = [ Html.text "No buttons here" ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButton "Submit"
                        ]
                        |> expectFailContaining "clickButton \"Submit\""
            ]
        , describe "form submission field extraction"
            [ test "preserves an empty string value attribute (value=\"\") instead of treating it as a bare boolean attribute" <|
                -- Regression test: `parseHtmlAttributes` previously coerced
                -- `value=""` to the literal string "true" because Elm's
                -- `Regex.find` returns `Nothing` for matched-but-empty
                -- captures, and the bare-attribute fallback fired by
                -- mistake. This matters for `Form.hiddenField` wrapping a
                -- `Field.checkbox` set to False, which renders as
                -- `value=""` -- the test runner must report the field as
                -- the empty string, not "true", so consumers see the same
                -- payload a real browser's `FormData` would produce.
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { capturedComplete = "(unset)" }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        CapturedSubmittedFields fields ->
                                            ( { model
                                                | capturedComplete =
                                                    fields
                                                        |> List.filter (\( name, _ ) -> name == "complete")
                                                        |> List.head
                                                        |> Maybe.map Tuple.second
                                                        |> Maybe.withDefault "(missing)"
                                              }
                                            , []
                                            )
                            , view =
                                \_ model ->
                                    { title = "Form"
                                    , body =
                                        [ Html.form
                                            [ Html.Events.preventDefaultOn "submit"
                                                (Decode.field "fields"
                                                    (Decode.list
                                                        (Decode.map2 Tuple.pair
                                                            (Decode.index 0 Decode.string)
                                                            (Decode.index 1 Decode.string)
                                                        )
                                                    )
                                                    |> Decode.map (\fields -> ( CapturedSubmittedFields fields, True ))
                                                )
                                            ]
                                            [ Html.input
                                                [ Attr.type_ "hidden"
                                                , Attr.name "complete"
                                                , Attr.value ""
                                                ]
                                                []
                                            , Html.button [] [ Html.text "Submit" ]
                                            ]
                                        , Html.text ("captured=[" ++ model.capturedComplete ++ "]")
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButton "Submit"
                        , PagesProgram.ensureViewHas [ PSelector.text "captured=[]" ]
                        ]
            ]
        , describe "fillIn"
            [ test "typing into an input updates the view" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Type to search..." ]
                        , PagesProgram.fillIn "search" "search" "elm-pages"
                        , PagesProgram.ensureViewHas [ PSelector.text "Searching for: elm-pages" ]
                        ]
            , test "fillIn fails on a disabled form field" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                        [ Html.form
                                            [ Attr.id "search-form"
                                            , Html.Events.on "input"
                                                (Decode.at [ "target", "value" ] Decode.string
                                                    |> Decode.map UpdateQuery
                                                )
                                            ]
                                            [ Html.input
                                                [ Attr.name "search"
                                                , Attr.disabled True
                                                , Attr.value model.query
                                                ]
                                                []
                                            ]
                                        , if String.isEmpty model.query then
                                            Html.text "Type to search..."

                                          else
                                            Html.text ("Searching for: " ++ model.query)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.fillIn "search-form" "search" "elm-pages"
                        ]
                        |> expectFailContaining "disabled"
            ]
        , describe "pressEnter"
            [ test "submits a form with no submit button when Enter is pressed in its input" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { todos = [], draft = "" }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        AddTodoFromInput ->
                                            ( { model
                                                | todos = model.todos ++ [ model.draft ]
                                                , draft = ""
                                              }
                                            , []
                                            )

                                        UpdateDraft d ->
                                            ( { model | draft = d }, [] )
                            , view =
                                \_ model ->
                                    { title = "Todos"
                                    , body =
                                        [ Html.form
                                            [ Attr.class "create"
                                            , Html.Events.onSubmit AddTodoFromInput
                                            ]
                                            [ Html.input
                                                [ Attr.id "new-todo"
                                                , Attr.value model.draft
                                                , Html.Events.onInput UpdateDraft
                                                ]
                                                []
                                            ]
                                        , Html.ul []
                                            (model.todos |> List.map (\t -> Html.li [] [ Html.text t ]))
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.fillIn "new-todo" "new-todo" "Buy milk"
                        , PagesProgram.pressEnter [ PSelector.id "new-todo" ]
                        , PagesProgram.ensureViewHas [ PSelector.tag "li", PSelector.text "Buy milk" ]
                        ]
            , test "fires keydown handler on the input even when there is no enclosing form" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { lastKey = "" }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        KeyPressed k ->
                                            ( { model | lastKey = k }, [] )
                            , view =
                                \_ model ->
                                    { title = "Keys"
                                    , body =
                                        [ Html.input
                                            [ Attr.id "free-input"
                                            , Html.Events.on "keydown"
                                                (Decode.field "key" Decode.string
                                                    |> Decode.map KeyPressed
                                                )
                                            ]
                                            []
                                        , Html.text ("last: " ++ model.lastKey)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.pressEnter [ PSelector.id "free-input" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "last: Enter" ]
                        ]
            , test "does not submit enclosing form when keydown prevents default" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { lastKey = "", submitCount = 0 }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        SubmittedForm ->
                                            ( { model | submitCount = model.submitCount + 1 }, [] )

                                        KeyDownPrevented key ->
                                            ( { model | lastKey = key }, [] )
                            , view =
                                \_ model ->
                                    { title = "Prevented"
                                    , body =
                                        [ Html.form
                                            [ Html.Events.onSubmit SubmittedForm ]
                                            [ Html.input
                                                [ Attr.id "prevented-input"
                                                , Html.Events.preventDefaultOn "keydown"
                                                    (Decode.field "key" Decode.string
                                                        |> Decode.map (\key -> ( KeyDownPrevented key, key == "Enter" ))
                                                    )
                                                ]
                                                []
                                            ]
                                        , Html.text ("last: " ++ model.lastKey)
                                        , Html.text ("submits=" ++ String.fromInt model.submitCount)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.pressEnter [ PSelector.id "prevented-input" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "last: Enter" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "submits=0" ]
                        ]
            , test "fails loudly when the selector matches no element" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Empty"
                                    , body = [ Html.input [ Attr.id "real-input" ] [] ]
                                    }
                            }
                        )
                        [ PagesProgram.pressEnter [ PSelector.id "missing" ]
                        ]
                        |> expectFailContaining "pressEnter"
            , test "fails loudly when the selector matches multiple elements" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Multi"
                                    , body =
                                        [ Html.form []
                                            [ Html.input [ Attr.class "edit-input" ] [] ]
                                        , Html.form []
                                            [ Html.input [ Attr.class "edit-input" ] [] ]
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.pressEnter [ PSelector.class "edit-input" ]
                        ]
                        |> Expect.all
                            [ expectFailContaining "pressEnter"
                            , expectFailContaining "multiple"
                            ]
            ]
        , describe "pressKey"
            [ test "fires a keydown with the given key on the matched element" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { lastKey = "" }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        KeyPressed k ->
                                            ( { model | lastKey = k }, [] )
                            , view =
                                \_ model ->
                                    { title = "Keys"
                                    , body =
                                        [ Html.input
                                            [ Attr.id "kb"
                                            , Html.Events.on "keydown"
                                                (Decode.field "key" Decode.string
                                                    |> Decode.map KeyPressed
                                                )
                                            ]
                                            []
                                        , Html.text ("last: " ++ model.lastKey)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.pressKey "Escape" [ PSelector.id "kb" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "last: Escape" ]
                        , PagesProgram.pressKey "ArrowDown" [ PSelector.id "kb" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "last: ArrowDown" ]
                        ]
            , test "does not auto-submit a form when pressKey Enter is used" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { submitCount = 0 }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        SubmittedForm ->
                                            ( { model | submitCount = model.submitCount + 1 }, [] )

                                        KeyDownPrevented _ ->
                                            ( model, [] )
                            , view =
                                \_ model ->
                                    { title = "Form"
                                    , body =
                                        [ Html.form
                                            [ Html.Events.onSubmit SubmittedForm ]
                                            [ Html.input [ Attr.id "f" ] [] ]
                                        , Html.text ("submits=" ++ String.fromInt model.submitCount)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.pressKey "Enter" [ PSelector.id "f" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "submits=0" ]
                        ]
            , test "fails loudly when the selector matches no element" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Empty"
                                    , body = [ Html.input [ Attr.id "real-input" ] [] ]
                                    }
                            }
                        )
                        [ PagesProgram.pressKey "Escape" [ PSelector.id "missing" ]
                        ]
                        |> expectFailContaining "pressKey \"Escape\""
            , test "fails loudly when the selector matches multiple elements" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Multi"
                                    , body =
                                        [ Html.input [ Attr.class "kb" ] []
                                        , Html.input [ Attr.class "kb" ] []
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.pressKey "Escape" [ PSelector.class "kb" ]
                        ]
                        |> Expect.all
                            [ expectFailContaining "pressKey \"Escape\""
                            , expectFailContaining "multiple"
                            ]
            ]
        , describe "simulateHttpGet for effects from update"
            [ test "simulateHttpGet resolves BackendTask effect from update" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Load Stars" ]
                        , PagesProgram.clickButton "Load Stars"
                        , PagesProgram.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 1234 ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Stars: 1234" ]
                        ]
            , test "simulateHttpGet works for BackendTask effects from update (not just data loading)" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Load Stars"
                        , PagesProgram.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 5678 ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Stars: 5678" ]
                        ]
            , test "simulateHttpPost can resolve the matching pending effect when a GET to the same URL is queued first" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { getResult = Nothing, postResult = Nothing }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        QueueSameUrlRequests ->
                                            ( model
                                            , [ BackendTask.Http.getJson
                                                    "https://api.example.com/items"
                                                    (Decode.field "value" Decode.string)
                                                    |> BackendTask.allowFatal
                                                    |> BackendTask.map GotGetResult
                                              , BackendTask.Http.request
                                                    { url = "https://api.example.com/items"
                                                    , method = "POST"
                                                    , headers = []
                                                    , body = BackendTask.Http.jsonBody (Encode.object [ ( "name", Encode.string "new item" ) ])
                                                    , retries = Nothing
                                                    , timeoutInMs = Nothing
                                                    }
                                                    (BackendTask.Http.expectJson (Decode.field "value" Decode.string))
                                                    |> BackendTask.allowFatal
                                                    |> BackendTask.map GotPostResult
                                              ]
                                            )

                                        GotGetResult value ->
                                            ( { model | getResult = Just value }, [] )

                                        GotPostResult value ->
                                            ( { model | postResult = Just value }, [] )
                            , view =
                                \_ model ->
                                    { title = "Request matching"
                                    , body =
                                        [ Html.button [ Html.Events.onClick QueueSameUrlRequests ] [ Html.text "Queue Requests" ]
                                        , Html.text ("Get: " ++ Maybe.withDefault "pending" model.getResult)
                                        , Html.text ("Post: " ++ Maybe.withDefault "pending" model.postResult)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButton "Queue Requests"
                        , PagesProgram.simulateHttpPost
                            "https://api.example.com/items"
                            (Encode.object [ ( "value", Encode.string "created" ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Post: created" ]
                        , PagesProgram.simulateHttpGet
                            "https://api.example.com/items"
                            (Encode.object [ ( "value", Encode.string "fetched" ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Get: fetched" ]
                        ]
            ]
        , describe "check"
            [ test "checking a checkbox updates the view" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Please accept terms" ]
                        , PagesProgram.check "I agree" True
                        , PagesProgram.ensureViewHas [ PSelector.text "Terms accepted" ]
                        ]
            ]
        , describe "Snapshots"
            [ test "toSnapshots records init snapshot" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        []
                        |> List.map .label
                        |> Expect.equal [ "start" ]
            , test "toSnapshots records each interaction" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "+1"
                        , PagesProgram.clickButton "+1"
                        , PagesProgram.ensureViewHas [ PSelector.text "2" ]
                        ]
                        |> List.map .label
                        |> Expect.equal [ "start", "clickButton \"+1\"", "clickButton \"+1\"", "ensureViewHas text \"2\"" ]
            , test "snapshots contain rendered HTML" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "+1"
                        ]
                        |> List.map .title
                        |> Expect.equal [ "Count: 0", "Count: 1" ]
            , test "error snapshots include the error" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.clickButton "Missing"
                        ]
                        |> List.length
                        |> Expect.equal 2
            , test "snapshot labels show selector details for ensureViewHas" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "0" ]
                        , PagesProgram.ensureViewHas [ PSelector.id "main" ]
                        , PagesProgram.ensureViewHas [ PSelector.class "counter" ]
                        , PagesProgram.ensureViewHas [ PSelector.tag "div" ]
                        , PagesProgram.ensureViewHasNot [ PSelector.text "Error" ]
                        ]
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas text \"0\""
                            , "ensureViewHas attribute \"id\" \"main\""
                            , "ensureViewHas class \"counter\""
                            , "ensureViewHas tag \"div\""
                            , "ensureViewHasNot text \"Error\""
                            ]
            , test "snapshot labels show multiple selectors comma-separated" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.tag "h1", PSelector.text "Welcome" ]
                        ]
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas tag \"h1\", text \"Welcome\""
                            ]
            , test "clickButtonWith snapshot labels show selector details" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                                \_ _ ->
                                    { title = "Home"
                                    , body =
                                        [ Html.button [ Attr.class "submit-btn", Html.Events.onClick Increment ] [ Html.text "Go" ] ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButtonWith [ PSelector.class "submit-btn" ]
                        ]
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "clickButtonWith class \"submit-btn\""
                            ]
            , test "withinFind adds scope label to assertion snapshots" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withinFind
                            [ PSelector.id "counter" ]
                            [ PagesProgram.ensureViewHas [ PSelector.text "0" ] ]
                        ]
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas text \"0\" (within attribute \"id\" \"counter\")"
                            ]
            , test "nested withinFind shows chained scope labels" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withinFind
                            [ PSelector.id "outer" ]
                            [ PagesProgram.withinFind
                                [ PSelector.class "inner" ]
                                [ PagesProgram.ensureViewHas [ PSelector.text "Hello" ] ]
 ]
                        ]
                        |> List.map .label
                        |> Expect.equal
                            [ "start"
                            , "ensureViewHas text \"Hello\" (within attribute \"id\" \"outer\" > class \"inner\")"
                            ]
            , test "assertion snapshots carry selector data for highlighting" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Hello", PSelector.class "greeting" ]
                        , PagesProgram.ensureViewHas [ PSelector.id "main" ]
                        , PagesProgram.ensureViewHas [ PSelector.tag "div" ]
                        ]
                        |> List.map .assertionSelectors
                        |> Expect.equal
                            [ [] -- start has no assertion selectors
                            , [ ByText "Hello", ByClass "greeting" ]
                            , [ ById_ "main" ]
                            , [ ByTag_ "div" ]
                            ]
            , test "ensureViewHasNot stores assertion selectors for highlighting" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Home"
                                    , body = [ Html.text "Hello" ]
                                    }
                            }
                        )
                        [ PagesProgram.ensureViewHasNot [ PSelector.text "Goodbye" ]
                        ]
                        |> List.map .assertionSelectors
                        |> Expect.equal
                            [ []
                            , [ ByText "Goodbye" ]
                            ]
            , test "value selectors stored in assertion snapshots" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                        ]
                        |> List.map .assertionSelectors
                        |> Expect.equal
                            [ []
                            , [ ByValue "Buy milk" ]
                            ]
            , test "withinFind snapshots carry scope selectors for highlighting" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withinFind
                            [ PSelector.id "counter" ]
                            [ PagesProgram.ensureViewHas [ PSelector.text "0" ] ]
                        ]
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ [] -- start
                            , [ [ ById_ "counter" ] ] -- assertion inside withinFind
                            ]
            , test "nested withinFind carries nested scope selectors" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withinFind
                            [ PSelector.id "outer" ]
                            [ PagesProgram.withinFind
                                [ PSelector.class "inner" ]
                                [ PagesProgram.ensureViewHas [ PSelector.text "Hello" ] ]
 ]
                        ]
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ [] -- start
                            , [ [ ById_ "outer" ], [ ByClass "inner" ] ] -- nested scopes
                            ]
            , test "clickButtonWith inside withinFind carries scope selectors" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                                \_ _ ->
                                    { title = "Scoped Click"
                                    , body =
                                        [ Html.div [ Attr.id "section-a" ]
                                            [ Html.button [ Attr.class "action-btn", Html.Events.onClick Increment ] [ Html.text "Do it" ] ]
                                        , Html.div [ Attr.id "section-b" ]
                                            [ Html.button [ Attr.class "action-btn", Html.Events.onClick Decrement ] [ Html.text "Do it" ] ]
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.withinFind
                            [ PSelector.id "section-a" ]
                            [ PagesProgram.clickButtonWith [ PSelector.class "action-btn" ] ]
                        ]
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ [] -- start
                            , [ [ ById_ "section-a" ] ] -- interaction inside withinFind
                            ]
            , test "non-scoped assertions have empty scope selectors" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Home"
                                    , body = [ Html.text "Hello" ]
                                    }
                            }
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Hello" ]
                        ]
                        |> List.map .scopeSelectors
                        |> Expect.equal
                            [ [] -- start
                            , [] -- no scope
                            ]
            ]
        , describe "disabled button detection"
            [ test "clickButton fails on disabled button" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Submit"
                        ]
                        |> expectFailContaining "disabled"
            , test "clickButton succeeds on enabled button" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Submit"
                        , PagesProgram.ensureViewHas [ PSelector.text "Clicked!" ]
                        ]
            , test "clickButtonWith fails on disabled button" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                    { title = "Form"
                                    , body =
                                        [ Html.button
                                            [ Attr.class "submit-btn"
                                            , Attr.disabled True
                                            , Html.Events.onClick Increment
                                            ]
                                            [ Html.text "Submit" ]
                                        , if model.clicked then
                                            Html.text "Should not appear!"

                                          else
                                            Html.text ""
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButtonWith [ PSelector.class "submit-btn" ]
                        ]
                        |> expectFailContaining "disabled"
            ]
        , describe "ambiguous button detection"
            [ test "clickButton fails when multiple buttons match" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Delete"
                        ]
                        |> expectFailContaining "Delete"
            , test "clickButtonWith fails when multiple buttons match selectors" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "List"
                                    , body =
                                        [ Html.button
                                            [ Attr.class "delete-btn", Html.Events.onClick () ]
                                            [ Html.text "Remove A" ]
                                        , Html.button
                                            [ Attr.class "delete-btn", Html.Events.onClick () ]
                                            [ Html.text "Remove B" ]
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButtonWith [ PSelector.class "delete-btn" ]
                        ]
                        |> expectFailContaining "multiple buttons"
            ]
        , describe "Bug fix: pending effects must not be overwritten"
            [ test "done fails when effects are pending after another interaction" <|
                \() ->
                    PagesProgram.expect
                        (-- Bug: clicking a button that triggers an effect, then clicking
                        -- another button before resolving, used to silently drop the effect.
                        -- After fix: done should fail because there's still a pending effect.
                        PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Fetch"
                        -- Click another button BEFORE resolving the effect
                        , PagesProgram.clickButton "Other"
                        -- done should fail: the HTTP effect from "Fetch" is still pending
                        ]
                        |> expectFailContaining "pending"
            , test "simulateHttpGet works after another interaction" <|
                \() ->
                    PagesProgram.expect
                        (-- The effect from the first click should survive a second click
                        PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Fetch"
                        , PagesProgram.clickButton "Other"
                        -- Should still be able to resolve the effect from "Fetch"
                        , PagesProgram.simulateHttpGet
                            "https://api.example.com/data"
                            (Encode.object [ ( "value", Encode.string "hello" ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Result: hello" ]
                        ]
            ]
        , describe "Bug fix: FatalError in data produces clean test failure"
            [ test "done fails cleanly when data BackendTask produces FatalError" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.fail (FatalError.fromString "Database connection failed")
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        []
                        |> expectFailContaining "Database connection failed"
            , test "ensureViewHas fails cleanly when data BackendTask produces FatalError" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.fail (FatalError.fromString "Service unavailable")
                            , init = \_ -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Hello" ]
                        ]
                        |> expectFailContaining "Service unavailable"
            ]
        , describe "simulateIncomingPort (elm-program-test style)"
            [ test "can simulate an incoming port message" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withSimulatedSubscriptions
                            (\_ ->
                                SimulatedSub.port_ "websocketReceived"
                                    (Decode.string |> Decode.map GotWebSocket)
                            )
                        , PagesProgram.ensureViewHas [ PSelector.text "No messages" ]
                        , PagesProgram.simulateIncomingPort "websocketReceived"
                            (Encode.string "hello")
                        , PagesProgram.ensureViewHas [ PSelector.text "hello" ]
                        , PagesProgram.simulateIncomingPort "websocketReceived"
                            (Encode.string "world")
                        , PagesProgram.ensureViewHas [ PSelector.text "hello, world" ]
                        ]
            , test "simulateIncomingPort fails when not subscribed to port" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.withSimulatedSubscriptions
                            (\_ -> SimulatedSub.none)
                        , PagesProgram.simulateIncomingPort "somePort"
                            (Encode.string "data")
                        ]
                        |> expectFailContaining "not currently subscribed"
            , test "simulateIncomingPort fails without withSimulatedSubscriptions" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.simulateIncomingPort "somePort"
                            (Encode.string "data")
                        ]
                        |> expectFailContaining "withSimulatedSubscriptions"
            , test "subscriptions are model-dependent" <|
                \() ->
                    PagesProgram.expect
                        (-- The subscription function re-evaluates with the current
                        -- model. When listening is False, port is not subscribed.
                        PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withSimulatedSubscriptions
                            (\model ->
                                if model.listening then
                                    SimulatedSub.port_ "dataPort"
                                        (Decode.string |> Decode.map ReceivedData)

                                else
                                    SimulatedSub.none
                            )
                        -- Not listening yet, so port should not be subscribed
                        , PagesProgram.simulateIncomingPort "dataPort"
                            (Encode.string "too early")
                        ]
                        |> expectFailContaining "not currently subscribed"
            ]
        , describe "ensureHttpGet"
            [ test "passes when a GET request to the URL is pending" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    (Decode.field "name" Decode.string)
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.ensureHttpGet "https://api.example.com/user"
                        , PagesProgram.simulateHttpGet
                            "https://api.example.com/user"
                            (Encode.object [ ( "name", Encode.string "Alice" ) ])
                        ]
            , test "fails when no GET request to the URL is pending" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed "static"
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.ensureHttpGet "https://api.example.com/user"
                        ]
                        |> expectFailContaining "https://api.example.com/user"
            , test "fails when the URL is wrong" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    (Decode.field "name" Decode.string)
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.ensureHttpGet "https://api.example.com/wrong-url"
                        ]
                        |> expectFailContaining "wrong-url"
            ]
        , describe "ensureCustom"
            [ test "passes when a custom BackendTask port is pending" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Custom.run "getTodos"
                                    Encode.null
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \todos -> ( { todos = todos }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Todos", body = [ Html.text model.todos ] }
                            }
                        )
                        [ PagesProgram.ensureCustom "getTodos" (\_ -> Expect.pass)
                        , PagesProgram.simulateCustom "getTodos" (Encode.string "[]")
                        ]
            , test "asserts on custom port arguments" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Custom.run "hashPassword"
                                    (Encode.string "secret123")
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \hash -> ( { hash = hash }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Hash", body = [ Html.text model.hash ] }
                            }
                        )
                        [ PagesProgram.ensureCustom "hashPassword"
                            (\args ->
                                Decode.decodeValue Decode.string args
                                    |> Expect.equal (Ok "secret123")
                            )
                        , PagesProgram.simulateCustom "hashPassword"
                            (Encode.string "hashed")
                        ]
            , test "fails when argument assertion fails, naming the port" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Custom.run "hashPassword"
                                    (Encode.string "actual-value")
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \hash -> ( { hash = hash }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Hash", body = [ Html.text model.hash ] }
                            }
                        )
                        [ PagesProgram.ensureCustom "hashPassword"
                            (\args ->
                                Decode.decodeValue Decode.string args
                                    |> Expect.equal (Ok "expected-value")
                            )
                        ]
                        |> Expect.all
                            [ expectFailContaining "ensureCustom"
                            , expectFailContaining "hashPassword"
                            , expectFailContaining "expected-value"
                            , expectFailContaining "actual-value"
                            ]
            ]
        , describe "ensureHttpPost"
            [ test "asserts on POST request body" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.post
                                    "https://api.example.com/items"
                                    (BackendTask.Http.jsonBody
                                        (Encode.object
                                            [ ( "name", Encode.string "test-item" ) ]
                                        )
                                    )
                                    (BackendTask.Http.expectJson Decode.string)
                                    |> BackendTask.allowFatal
                            , init = \value -> ( { value = value }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Items", body = [ Html.text model.value ] }
                            }
                        )
                        [ PagesProgram.ensureHttpPost "https://api.example.com/items"
                            (\body ->
                                Decode.decodeValue (Decode.field "name" Decode.string) body
                                    |> Expect.equal (Ok "test-item")
                            )
                        , PagesProgram.simulateHttpPost "https://api.example.com/items"
                            (Encode.string "ok")
                        ]
            , test "fails when body assertion fails, naming the URL" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.post
                                    "https://api.example.com/items"
                                    (BackendTask.Http.jsonBody
                                        (Encode.object
                                            [ ( "name", Encode.string "actual" ) ]
                                        )
                                    )
                                    (BackendTask.Http.expectJson Decode.string)
                                    |> BackendTask.allowFatal
                            , init = \value -> ( { value = value }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Items", body = [ Html.text model.value ] }
                            }
                        )
                        [ PagesProgram.ensureHttpPost "https://api.example.com/items"
                            (\body ->
                                Decode.decodeValue (Decode.field "name" Decode.string) body
                                    |> Expect.equal (Ok "expected")
                            )
                        ]
                        |> Expect.all
                            [ expectFailContaining "ensureHttpPost"
                            , expectFailContaining "api.example.com/items"
                            , expectFailContaining "expected"
                            , expectFailContaining "actual"
                            ]
            ]
        , describe "simulateHttpError"
            [ test "simulates a network error on data loading" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/data"
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \value -> ( { value = value }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Data", body = [ Html.text model.value ] }
                            }
                        )
                        [ PagesProgram.simulateHttpError "GET"
                            "https://api.example.com/data"
                            NetworkError
                        ]
                        |> expectFailContaining "NetworkError"
            , test "simulates a timeout on data loading" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/data"
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \value -> ( { value = value }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Data", body = [ Html.text model.value ] }
                            }
                        )
                        [ PagesProgram.simulateHttpError "GET"
                            "https://api.example.com/data"
                            Timeout
                        ]
                        |> expectFailContaining "Timeout"
            ]
        , describe "HTTP simulation error messages"
            [ test "simulateHttpPost with no pending requests shows the URL you tried" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed "ready"
                            , init = \msg -> ( { text = msg }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Test", body = [ Html.text model.text ] }
                            }
                        )
                        [ PagesProgram.simulateHttpPost
                            "https://api.example.com/data"
                            (Encode.object [])
                        ]
                        |> expectFailContaining "api.example.com/data"
            , test "simulateHttpGet with no pending requests shows the URL you tried" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed "ready"
                            , init = \msg -> ( { text = msg }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Test", body = [ Html.text model.text ] }
                            }
                        )
                        [ PagesProgram.simulateHttpGet
                            "https://api.example.com/users"
                            (Encode.object [])
                        ]
                        |> expectFailContaining "api.example.com/users"
            , test "simulateHttpPost with wrong URL shows both the attempted URL and the pending request" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/actual-endpoint"
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.simulateHttpPost
                            "https://api.example.com/wrong-endpoint"
                            (Encode.object [])
                        ]
                        |> Expect.all
                            [ expectFailContaining "wrong-endpoint"
                            , expectFailContaining "actual-endpoint"
                            ]
            ]
        , describe "selectOption"
            [ test "selecting a dropdown option updates the view" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Selected: red" ]
                        , PagesProgram.selectOption "Favorite Color" "Blue"
                        , PagesProgram.ensureViewHas [ PSelector.text "Selected: blue" ]
                        ]
            , test "selectOption fails when no label matches" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "No selects" ] }
                            }
                        )
                        [ PagesProgram.selectOption "Missing" "text"
                        ]
                        |> expectFailContaining "selectOption"
            , test "selectOption fails when the option text does not exist" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.selectOption "Favorite Color" "Not Blue"
                        ]
                        |> expectFailContaining "Not Blue"
            , test "selectOption fails on a disabled select" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                            , Attr.disabled True
                                            , Html.Events.onInput SelectColor
                                            ]
                                            [ Html.option [ Attr.value "red" ] [ Html.text "Red" ]
                                            , Html.option [ Attr.value "blue" ] [ Html.text "Blue" ]
                                            ]
                                        , Html.text ("Selected: " ++ model.color)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.selectOption "Favorite Color" "Blue"
                        ]
                        |> expectFailContaining "disabled"
            , test "selectOption fails on a disabled option" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                            , Html.option [ Attr.value "blue", Attr.disabled True ] [ Html.text "Blue" ]
                                            ]
                                        , Html.text ("Selected: " ++ model.color)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.selectOption "Favorite Color" "Blue"
                        ]
                        |> expectFailContaining "disabled"
            , test "selectOption fails when multiple labels match" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Form"
                                    , body =
                                        [ Html.label [ Attr.for "size-1" ] [ Html.text "Size" ]
                                        , Html.select [ Attr.id "size-1" ]
                                            [ Html.option [ Attr.value "s" ] [ Html.text "Small" ] ]
                                        , Html.label [ Attr.for "size-2" ] [ Html.text "Size" ]
                                        , Html.select [ Attr.id "size-2" ]
                                            [ Html.option [ Attr.value "m" ] [ Html.text "Medium" ] ]
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.selectOption "Size" "Small"
                        ]
                        |> expectFailContaining "multiple"
            ]
        , describe "expectViewHas (terminal assertion)"
            [ test "passes when view has selector" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Hello" ]
                        ]
            , test "fails when view does not have selector" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Goodbye" ]
                        ]
                        |> expectFailContaining "Goodbye"
            ]
        , describe "cookie jar"
            [ test "CookieJar.init has no cookies" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.get "anything"
                        |> Expect.equal Nothing
            , test "CookieJar.set adds a cookie" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.set "theme" "dark"
                        |> CookieJar.get "theme"
                        |> Expect.equal (Just "dark")
            , test "CookieJar.fromSetCookieHeaders parses Set-Cookie headers" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "session=abc123; Path=/; HttpOnly"
                            , "theme=dark; Path=/"
                            ]
                        |> CookieJar.get "session"
                        |> Expect.equal (Just "abc123")
            , test "CookieJar.toCookieDict produces dict for request" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.set "a" "1"
                        |> CookieJar.set "b" "2"
                        |> CookieJar.toDict
                        |> Dict.get "a"
                        |> Expect.equal (Just "1")
            , test "Set-Cookie with multiple attributes parsed correctly" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "token=xyz789; Path=/; Domain=.example.com; Secure; HttpOnly; SameSite=Strict; Max-Age=3600" ]
                        |> CookieJar.get "token"
                        |> Expect.equal (Just "xyz789")
            , test "multiple Set-Cookie headers accumulate" <|
                \() ->
                    let
                        jar : CookieJar.CookieJar
                        jar =
                            CookieJar.init
                                |> CookieJar.withSetCookieHeaders
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
                    CookieJar.init
                        |> CookieJar.set "theme" "light"
                        |> CookieJar.withSetCookieHeaders
                            [ "theme=dark; Path=/" ]
                        |> CookieJar.get "theme"
                        |> Expect.equal (Just "dark")
            , test "URL-encoded cookie values are decoded" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "data=hello%20world; Path=/" ]
                        |> CookieJar.get "data"
                        |> Expect.equal (Just "hello world")
            ]
        , describe "startWithEffects (custom Effect type simulation)"
            [ test "user-defined effects are converted to BackendTasks" <|
                \() ->
                    PagesProgram.expect
                        (-- Users have a custom Effect type. They provide a function
                        -- to convert it to BackendTasks the framework can handle.
                        PagesProgramInternal.initialProgramTestWithEffects
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "No name" ]
                        , PagesProgram.clickButton "Load"
                        , PagesProgram.simulateHttpGet
                            "https://api.example.com/data"
                            (Encode.object [ ( "name", Encode.string "Alice" ) ])
                        , PagesProgram.ensureViewHas [ PSelector.text "Name: Alice" ]
                        ]
            ]
        , describe "effect tracking"
            [ test "done reports count of unresolved effects" <|
                \() ->
                    PagesProgram.expect
                        (-- When there are pending effects at the end, done should
                        -- report how many AND describe what's pending
                        PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Go"
                        ]
                        |> expectFailContaining "1 pending"
            , test "multiple effects from different interactions all tracked" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                \_ _ ->
                                    { title = "Effect"
                                    , body =
                                        [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ]
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButton "Go"
                        , PagesProgram.clickButton "Go"
                        ]
                        |> expectFailContaining "2 pending"
            , test "done describes what effects are pending" <|
                \() ->
                    PagesProgram.expect
                        (-- done should include the URLs of pending HTTP requests
                        PagesProgramInternal.initialProgramTest
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
                                \_ _ ->
                                    { title = "Effect"
                                    , body =
                                        [ Html.button [ Html.Events.onClick TriggerEffect ] [ Html.text "Go" ] ]
                                    }
                            }
                        )
                        [ PagesProgram.clickButton "Go"
                        ]
                        |> expectFailContaining "api.example.com"
            ]
        , describe "unsupported Platform effects"
            [ test "RunCmd is reported as unsupported instead of silently ignored" <|
                \() ->
                    PagesProgramInternal.unsupportedPlatformEffectError (Platform.RunCmd Cmd.none)
                        |> Maybe.withDefault ""
                        |> Expect.all
                            [ \message -> message |> String.contains "RunCmd" |> Expect.equal True
                            , \message -> message |> String.contains "cannot simulate" |> Expect.equal True
                            ]
            , test "BrowserLoadUrl is reported as unsupported instead of silently ignored" <|
                \() ->
                    PagesProgramInternal.unsupportedPlatformEffectError (Platform.BrowserLoadUrl "https://example.com")
                        |> Maybe.withDefault ""
                        |> Expect.all
                            [ \message -> message |> String.contains "BrowserLoadUrl" |> Expect.equal True
                            , \message -> message |> String.contains "https://example.com" |> Expect.equal True
                            ]
            ]
        , describe "SimulatedEffect.submitFetcher payload conversion"
            [ test "fetcher form data preserves fields and defaults action to the current path" <|
                \() ->
                    Pages.Fetcher.submit
                        (Bytes.Decode.string 2)
                        { fields = [ ( "title", "Buy milk" ) ], headers = [] }
                        |> PagesProgramInternal.fetcherToFormData "/todos"
                        |> Expect.equal
                            { fields = [ ( "title", "Buy milk" ) ]
                            , method = Form.Post
                            , action = "/todos"
                            , id = Nothing
                            }
            , test "fetcher form data preserves an explicit fetcher URL" <|
                \() ->
                    Pages.Fetcher.Fetcher
                        { decoder = \_ -> Ok "done"
                        , fields = [ ( "id", "todo-1" ) ]
                        , headers = []
                        , url = Just "/todos/todo-1"
                        }
                        |> PagesProgramInternal.fetcherToFormData "/todos"
                        |> Expect.equal
                            { fields = [ ( "id", "todo-1" ) ]
                            , method = Form.Post
                            , action = "/todos/todo-1"
                            , id = Nothing
                            }
            ]
        , describe "withModelInspector"
            [ test "annotates every snapshot when applied to the starting program" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                            |> PagesProgram.withModelInspector
                                (\model -> "count=" ++ String.fromInt model.count)
                        )
                        [ PagesProgram.clickButton "+1"
                        , PagesProgram.clickButton "+1"
                        ]
                        |> List.map .modelState
                        |> Expect.equal
                            [ Just "count=0"
                            , Just "count=1"
                            , Just "count=2"
                            ]
            ]
        , describe "within (DOM scoping)"
            [ test "scopes clickButton to a specific element" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withinFind
                            [ Selector.id "section-b" ]
                            [ PagesProgram.clickButton "+1" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "A: 0" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "B: 1" ]
                        ]
            , test "within resets scope after block" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.withinFind
                            [ Selector.id "section-b" ]
                            [ PagesProgram.clickButton "+1" ]
                        -- After within, scope resets to full view.
                        -- Use within again to target section-a specifically.
                        , PagesProgram.withinFind
                            [ Selector.id "section-a" ]
                            [ PagesProgram.clickButton "+1" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "A: 1" ]
                        , PagesProgram.ensureViewHas [ PSelector.text "B: 1" ]
                        ]
            ]
        , describe "fillInTextarea"
            [ test "fills in a textarea by finding the first one" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.fillInTextarea "Hello from textarea!"
                        , PagesProgram.ensureViewHas [ PSelector.text "Content: Hello from textarea!" ]
                        ]
            ]
        , describe "expectView (terminal)"
            [ test "passes with custom query assertion" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureView
                            (Query.find [ Selector.id "main" ]
                                >> Query.has [ Selector.tag "h1" ]
                            )
                        ]
            , test "fails with useful message" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureView
                            (Query.has [ Selector.id "nonexistent" ])
                        ]
                        |> expectFailContaining "id"
            ]
        , describe "simulateDomEvent"
            [ test "simulates a custom event on a targeted element" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Not focused" ]
                        , PagesProgram.simulateDomEvent
                            (Query.find [ Selector.id "my-input" ])
                            Event.focus
                        , PagesProgram.ensureViewHas [ PSelector.text "Focused!" ]
                        ]
            ]
        , describe "clickLink"
            [ test "clickLink extracts href from DOM and navigates" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickLink "About"
                        , PagesProgram.ensureViewHas [ PSelector.text "Page: /about" ]
                        ]
            , test "clickLink fails when link text not found" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Page"
                                    , body = [ Html.text "No links here" ]
                                    }
                            }
                        )
                        [ PagesProgram.clickLink "Go somewhere"
                        ]
                        |> expectFailContaining "clickLink"
            , test "clickLink navigates using href from the DOM, not user-supplied" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                            [ Attr.href "/the-real-href"
                                            , Html.Events.onClick (Navigate "/the-real-href")
                                            ]
                                            [ Html.text "Click me" ]
                                        , Html.text ("Page: " ++ model.page)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.clickLink "Click me"
                        , PagesProgram.ensureViewHas [ PSelector.text "Page: /the-real-href" ]
                        ]
            , test "clickLink fails with helpful message when multiple links match" <|
                \() ->
                    case
                        Test.Runner.getFailureReason
                            (PagesProgram.expect
                                (PagesProgramInternal.initialProgramTest
                                    { data = BackendTask.succeed ()
                                    , init = \() -> ( {}, [] )
                                    , update = \_ model -> ( model, [] )
                                    , view =
                                        \_ _ ->
                                            { title = "Nav"
                                            , body =
                                                [ Html.a [ Attr.href "/about" ] [ Html.text "Click me" ]
                                                , Html.a [ Attr.href "/contact" ] [ Html.text "Click me" ]
                                                ]
                                            }
                                    }
                                )
                                [ PagesProgram.clickLink "Click me" ]
                            )
                    of
                        Nothing ->
                            Expect.fail "Expected test to fail, but it passed"

                        Just { description } ->
                            description
                                |> Expect.all
                                    [ \d ->
                                        d
                                            |> String.contains "found multiple links with that text"
                                            |> Expect.equal True
                                    , \d ->
                                        d
                                            |> String.contains "withinFind"
                                            |> Expect.equal True
                                    , \d ->
                                        d
                                            |> String.contains "<a href=\"/about\">"
                                            |> Expect.equal True
                                    , \d ->
                                        d
                                            |> String.contains "<a href=\"/contact\">"
                                            |> Expect.equal True
                                    ]
            , test "clickLink fails when no <a> element has the given text" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Nav"
                                    , body =
                                        [ Html.a [ Attr.href "/about" ] [ Html.text "About" ]
                                        , Html.span [] [ Html.text "Not a link" ]
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.clickLink "Not a link"
                        ]
                        |> expectFailContaining "clickLink"
            , test "clickLink gives helpful error when <a> has no href" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Nav"
                                    , body =
                                        [ Html.a [] [ Html.text "Broken link" ] ]
                                    }
                            }
                        )
                        [ PagesProgram.clickLink "Broken link"
                        ]
                        |> expectFailContaining "href"
            ]
        , describe "navigateTo"
            [ test "navigateTo fails without startPlatform" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.navigateTo "/about"
                        ]
                        |> expectFailContaining "Navigation is only supported"
            , test "navigateTo fails while data is resolving" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/data"
                                    Decode.string
                                    |> BackendTask.allowFatal
                            , init = \_ -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.navigateTo "/about"
                        ]
                        |> expectFailContaining "resolving"
            ]
        , describe "ensureBrowserUrl"
            [ test "ensureBrowserUrl fails without startPlatform" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureBrowserUrl
                            (\url -> url |> Expect.equal "anything")
                        ]
                        |> expectFailContaining "URL tracking is only supported"
            ]
        , describe "fillInTextarea errors"
            [ test "fillInTextarea fails when no textarea found" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "No textarea" ] }
                            }
                        )
                        [ PagesProgram.fillInTextarea "some text"
                        ]
                        |> expectFailContaining "fillInTextarea"
            , test "fillInTextarea fails on a disabled textarea" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( { content = "" }, [] )
                            , update =
                                \msg model ->
                                    case msg of
                                        UpdateContent content ->
                                            ( { model | content = content }, [] )
                            , view =
                                \_ model ->
                                    { title = "Editor"
                                    , body =
                                        [ Html.textarea
                                            [ Attr.disabled True
                                            , Html.Events.onInput UpdateContent
                                            ]
                                            [ Html.text model.content ]
                                        , Html.text ("Content: " ++ model.content)
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.fillInTextarea "some text"
                        ]
                        |> expectFailContaining "disabled"
            ]
        , describe "simulateDomEvent errors"
            [ test "simulateDomEvent fails when element not found" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.simulateDomEvent
                            (Query.find [ Selector.id "missing" ])
                            Event.focus
                        ]
                        |> expectFailContaining "simulateDomEvent"
            ]
        , describe "selectOption errors"
            [ test "selectOption fails when select not found" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "No select" ] }
                            }
                        )
                        [ PagesProgram.selectOption "Label" "text"
                        ]
                        |> expectFailContaining "selectOption"
            ]
        , describe "CookieJar edge cases"
            [ test "malformed Set-Cookie without name=value is ignored" <|
                \() ->
                    -- "Path=/; HttpOnly" is not a valid cookie, just attributes
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "Path=/; HttpOnly" ]
                        |> CookieJar.get "Path"
                        |> Expect.equal Nothing
            ]
        , describe "within error handling"
            [ test "within gives clear error when scope element doesn't exist" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.withinFind
                            [ Selector.id "nonexistent" ]
                            [ PagesProgram.ensureViewHas [ PSelector.text "anything" ] ]
                        ]
                        |> expectFailContaining "nonexistent"
            ]
        , describe "textarea support (legacy)"
            [ test "fillIn works with textarea" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.fillIn "editor" "editor" "Hello textarea!"
                        , PagesProgram.ensureViewHas [ PSelector.text "Content: Hello textarea!" ]
                        ]
            ]
        , describe "SimulatedEffect (Effect.testPerform integration)"
            [ test "startWithEffects with SimulatedEffect-style decomposition" <|
                \() ->
                    PagesProgram.expect
                        (-- The startWithEffects path converts custom effects to BackendTasks.
                        -- When an effect is pure (no HTTP needed), use BackendTask.succeed
                        -- Pure effects (BackendTask.succeed msg) auto-resolve immediately.
                        PagesProgramInternal.initialProgramTestWithEffects
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
                        )
                        [ PagesProgram.ensureViewHas [ PSelector.text "Message: initial" ]
                        , PagesProgram.clickButton "Chain"
                        , PagesProgram.ensureViewHas [ PSelector.text "Message: chained!" ]
                        ]
            , test "SimulatedEffect.map preserves message transformation" <|
                \() ->
                    -- Verify that SimulatedEffect.map correctly transforms messages
                    let
                        original : SimulatedEffect.SimulatedEffect Int
                        original =
                            SimulatedEffect.dispatchMsg 42

                        mapped : SimulatedEffect.SimulatedEffect String
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
                        original : SimulatedEffect.SimulatedEffect Int
                        original =
                            SimulatedEffect.batch
                                [ SimulatedEffect.dispatchMsg 1
                                , SimulatedEffect.none
                                , SimulatedEffect.dispatchMsg 2
                                ]

                        mapped : SimulatedEffect.SimulatedEffect Int
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
                        mapped : SimulatedEffect.SimulatedEffect String
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
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureBrowserUrl
                            (\url -> url |> Expect.equal "anything")
                        ]
                        |> expectFailContaining "URL tracking is only supported"
            ]
        , describe "ensureBrowserHistory / expectBrowserHistory"
            [ test "ensureBrowserHistory fails without startPlatform" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureBrowserHistory
                            (\history -> Expect.equal [] history)
                        ]
                        |> expectFailContaining "only supported with generated TestApp.start"
            , test "expectBrowserHistory fails without startPlatform" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Home", body = [ Html.text "Hello" ] }
                            }
                        )
                        [ PagesProgram.ensureBrowserHistory
                            (\history -> Expect.equal [] history)
                        ]
                        |> expectFailContaining "only supported with generated TestApp.start"
            ]
        , describe "check with label"
            [ test "check verifies label is associated with the checkbox" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.check "I agree to the terms" True
                        , PagesProgram.ensureViewHas [ PSelector.text "Terms accepted" ]
                        ]
            , test "check fails when label doesn't match" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.check "Wrong label text" True
                        ]
                        |> expectFailContaining "Could not find"
            , test "check works with label wrapping the input" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                                [ Attr.type_ "checkbox"
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
                        )
                        [ PagesProgram.check "Accept terms" True
                        , PagesProgram.ensureViewHas [ PSelector.text "Terms accepted" ]
                        ]
            , test "check fails on a disabled checkbox" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
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
                                            , Attr.disabled True
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
                        )
                        [ PagesProgram.check "I agree to the terms" True
                        ]
                        |> expectFailContaining "disabled"
            , test "check fails when multiple checkboxes match the label" <|
                \() ->
                    PagesProgram.expect
                        (PagesProgramInternal.initialProgramTest
                            { data = BackendTask.succeed ()
                            , init = \() -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view =
                                \_ _ ->
                                    { title = "Form"
                                    , body =
                                        [ Html.label [ Attr.for "opt-a" ] [ Html.text "Enable" ]
                                        , Html.input [ Attr.id "opt-a", Attr.type_ "checkbox" ] []
                                        , Html.label [ Attr.for "opt-b" ] [ Html.text "Enable" ]
                                        , Html.input [ Attr.id "opt-b", Attr.type_ "checkbox" ] []
                                        ]
                                    }
                            }
                        )
                        [ PagesProgram.check "Enable" True
                        ]
                        |> expectFailContaining "multiple"
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
        , describe "Network entry enrichment"
            [ test "GET request has no requestBody" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    (Decode.field "name" Decode.string)
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.simulateHttpGet
                            "https://api.example.com/user"
                            (Encode.object [ ( "name", Encode.string "Alice" ) ])
                        ]
                        |> List.concatMap .networkLog
                        |> List.filter (\e -> e.url == "https://api.example.com/user")
                        |> List.head
                        |> Maybe.map .requestBody
                        |> Expect.equal (Just Nothing)
            , test "POST request captures requestBody as pretty-printed JSON" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.request
                                    { url = "https://api.example.com/graphql"
                                    , method = "POST"
                                    , headers = []
                                    , body = BackendTask.Http.jsonBody (Encode.object [ ( "query", Encode.string "{ users }" ) ])
                                    , retries = Nothing
                                    , timeoutInMs = Nothing
                                    }
                                    (BackendTask.Http.expectJson (Decode.field "data" Decode.string))
                                    |> BackendTask.allowFatal
                            , init = \result -> ( { text = result }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "Test", body = [ Html.text model.text ] }
                            }
                        )
                        [ PagesProgram.simulateHttpPost
                            "https://api.example.com/graphql"
                            (Encode.object [ ( "data", Encode.string "ok" ) ])
                        ]
                        |> List.concatMap .networkLog
                        |> List.filter (\e -> e.url == "https://api.example.com/graphql")
                        |> List.head
                        |> Maybe.map .requestBody
                        |> Expect.equal (Just (Just "{\n  \"query\": \"{ users }\"\n}"))
            , test "POST request captures requestHeaders" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.request
                                    { url = "https://api.example.com/data"
                                    , method = "POST"
                                    , headers = [ ( "Authorization", "Bearer token123" ), ( "X-Custom", "value" ) ]
                                    , body = BackendTask.Http.jsonBody (Encode.object [ ( "key", Encode.string "val" ) ])
                                    , retries = Nothing
                                    , timeoutInMs = Nothing
                                    }
                                    (BackendTask.Http.expectJson (Decode.field "ok" Decode.bool))
                                    |> BackendTask.allowFatal
                            , init = \_ -> ( {}, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ _ -> { title = "Test", body = [ Html.text "ok" ] }
                            }
                        )
                        [ PagesProgram.simulateHttpPost
                            "https://api.example.com/data"
                            (Encode.object [ ( "ok", Encode.bool True ) ])
                        ]
                        |> List.concatMap .networkLog
                        |> List.filter (\e -> e.url == "https://api.example.com/data")
                        |> List.head
                        |> Maybe.map (.requestHeaders >> List.filter (\( name, _ ) -> not (String.startsWith "elm-pages-internal" name)))
                        |> Expect.equal (Just [ ( "Authorization", "Bearer token123" ), ( "X-Custom", "value" ) ])
            , test "response preview is captured" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
                            { data =
                                BackendTask.Http.getJson
                                    "https://api.example.com/user"
                                    (Decode.field "name" Decode.string)
                                    |> BackendTask.allowFatal
                            , init = \name -> ( { name = name }, [] )
                            , update = \_ model -> ( model, [] )
                            , view = \_ model -> { title = "User", body = [ Html.text model.name ] }
                            }
                        )
                        [ PagesProgram.simulateHttpGet
                            "https://api.example.com/user"
                            (Encode.object [ ( "name", Encode.string "Alice" ) ])
                        ]
                        |> List.concatMap .networkLog
                        |> List.filter (\e -> e.url == "https://api.example.com/user" && e.status == Stubbed)
                        |> List.head
                        |> Maybe.andThen .responsePreview
                        |> Expect.equal (Just "{\n  \"name\": \"Alice\"\n}")
            , test "simulateHttpError marks the network entry as failed" <|
                \() ->
                    PagesProgram.snapshots
                        (PagesProgramInternal.initialProgramTest
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
                        )
                        [ PagesProgram.clickButton "Load Stars"
                        , PagesProgram.simulateHttpError
                            "GET"
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            NetworkError
                        ]
                        |> List.concatMap .networkLog
                        |> List.filter
                            (\e ->
                                e.url
                                    == "https://api.github.com/repos/dillonkearns/elm-pages"
                                    && e.status
                                    == Failed
                            )
                        |> List.head
                        |> Maybe.andThen .responsePreview
                        |> Expect.equal (Just "NetworkError")
            ]
        ]


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


type TodoFormMsg
    = AddTodoFromInput
    | UpdateDraft String


type KeyboardMsg
    = KeyPressed String


type FormMsg
    = SubmittedForm
    | KeyDownPrevented String


type CheckMsg
    = ToggleAgreed Bool


type StarsMsg
    = FetchStars
    | GotStars Int


type QueueMsg
    = QueueFetch
    | DoOtherThing
    | GotResult String


type RequestMatchingMsg
    = QueueSameUrlRequests
    | GotGetResult String
    | GotPostResult String


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


type CapturedFieldsMsg
    = CapturedSubmittedFields (List ( String, String ))


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
