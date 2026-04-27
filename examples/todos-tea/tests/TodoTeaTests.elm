module TodoTeaTests exposing (suite)

{-| End-to-end tests for the TEA-focused TodoMVC.

Demonstrates the integration of BackendTask data loading (server) with
client-side TEA interactions (no server round-trips for mutations).

Contrast with the original todos example where every mutation goes
through a server action.

View in browser: elm-pages dev, then open /\_tests

-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import TestApp
import Time


suite : PagesProgram.Test
suite =
    PagesProgram.describe "TodoMVC (TEA-focused)"
        [ PagesProgram.describe "Auth"
            [ PagesProgram.test "completes the magic-link login flow"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ PagesProgram.ensureBrowserUrl
                            (\url ->
                                if String.contains "/login" url then
                                    Expect.fail ("Should have redirected away from /login, but still at: " ++ url)

                                else
                                    Expect.pass
                            )
                       , PagesProgram.ensureViewHas [ Selector.text "todos" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]
                       , ensureItemsLeft 2
                       ]
                )
            ]
        , PagesProgram.describe "Todo management"
            [ PagesProgram.test "adds a todo via Enter"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ ensureItemsLeft 2
                       , typeNewTodo "Buy eggs"
                       , PagesProgram.pressEnter [ Selector.class "new-todo" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Buy eggs" ]
                       , ensureItemsLeft 3
                       ]
                )
            , PagesProgram.test "toggles a todo's completion"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ ensureItemsLeft 2
                       , toggleTodo "Buy milk"
                       , ensureItemsLeft 1
                       , toggleTodo "Buy milk"
                       , ensureItemsLeft 2
                       ]
                )
            , PagesProgram.test "deletes a todo"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
                       , PagesProgram.withinFind
                            [ Selector.tag "li"
                            , Selector.containing [ Selector.text "Write tests" ]
                            ]
                            [ PagesProgram.clickButtonWith [ Selector.class "destroy" ] ]
                       , PagesProgram.ensureViewHasNot [ Selector.text "Write tests" ]
                       , ensureItemsLeft 2
                       ]
                )
            , PagesProgram.test "toggles all todos with the toggle-all checkbox"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ ensureItemsLeft 2
                       , clickToggleAll
                       , ensureItemsLeft 0
                       , clickToggleAll
                       , ensureItemsLeft 3
                       ]
                )
            , PagesProgram.test "clears completed todos"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
                       , PagesProgram.clickButton "Clear completed (1)"
                       , PagesProgram.ensureViewHasNot [ Selector.text "Write tests" ]
                       , ensureItemsLeft 2
                       ]
                )
            , PagesProgram.test "adds multiple todos in sequence"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ ensureItemsLeft 2
                       , typeNewTodo "First new todo"
                       , PagesProgram.pressEnter [ Selector.class "new-todo" ]
                       , PagesProgram.ensureViewHas [ Selector.text "First new todo" ]
                       , typeNewTodo "Second new todo"
                       , PagesProgram.pressEnter [ Selector.class "new-todo" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Second new todo" ]
                       , ensureItemsLeft 4
                       ]
                )
            ]
        , PagesProgram.describe "Filtering"
            [ PagesProgram.test "switches All / Active / Completed filter views"
                startLoggedIn
                (loginAndLoadTodos
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]
                       , clickFilter "Active"
                       , PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
                       , PagesProgram.ensureViewHasNot [ Selector.text "Write tests" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]
                       , clickFilter "Completed"
                       , PagesProgram.ensureViewHasNot [ Selector.text "Buy milk" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
                       , PagesProgram.ensureViewHasNot [ Selector.text "Walk the dog" ]
                       , clickFilter "All"
                       , PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]
                       ]
                )
            ]
        ]



-- SETUP


baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withTime (Time.millisToPosix 1000)


startLoggedIn : TestApp.ProgramTest
startLoggedIn =
    TestApp.start "/login?magic=fake-hash" baseSetup


loginAndLoadTodos =
    [ PagesProgram.simulateCustom "decrypt" decryptResponse
    , PagesProgram.simulateCustom "findOrCreateUserAndSession" sessionIdResponse
    , PagesProgram.simulateCustom "getTodosBySession" todosResponse
    ]


decryptResponse : Encode.Value
decryptResponse =
    Encode.string "{\"text\":\"user@example.com\",\"expiresAt\":99999999999999}"


sessionIdResponse : Encode.Value
sessionIdResponse =
    Encode.string "test-session-id"


todosResponse : Encode.Value
todosResponse =
    Encode.list identity
        [ Encode.object
            [ ( "title", Encode.string "Buy milk" )
            , ( "complete", Encode.bool False )
            , ( "id", Encode.string "1" )
            ]
        , Encode.object
            [ ( "title", Encode.string "Write tests" )
            , ( "complete", Encode.bool True )
            , ( "id", Encode.string "2" )
            ]
        , Encode.object
            [ ( "title", Encode.string "Walk the dog" )
            , ( "complete", Encode.bool False )
            , ( "id", Encode.string "3" )
            ]
        ]



-- HELPERS


ensureItemsLeft n =
    PagesProgram.ensureViewHas
        [ Selector.tag "span"
        , Selector.class "todo-count"
        , Selector.containing [ Selector.text (String.fromInt n) ]
        ]


typeNewTodo content =
    PagesProgram.simulateDomEvent
        (\query -> query |> Query.find [ Selector.class "new-todo" ])
        (Event.input content)


toggleTodo description =
    PagesProgram.withinFind
        [ Selector.tag "li"
        , Selector.containing [ Selector.text description ]
        ]
        [ PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ Selector.class "toggle" ])
            Event.click
        ]


clickToggleAll =
    PagesProgram.simulateDomEvent
        (\query -> query |> Query.find [ Selector.class "toggle-all" ])
        Event.click


clickFilter filterName =
    PagesProgram.withinFind
        [ Selector.class "filters" ]
        [ PagesProgram.simulateDomEvent
            (\query ->
                query
                    |> Query.find
                        [ Selector.tag "a"
                        , Selector.containing [ Selector.text filterName ]
                        ]
            )
            Event.click
        ]
