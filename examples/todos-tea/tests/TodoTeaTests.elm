module TodoTeaTests exposing
    ( fullLoginFlowTest
    , addTodoTest
    , toggleTodoTest
    , deleteTodoTest
    , toggleAllTest
    , clearCompletedTest
    , filterViewTest
    , addMultipleTodosTest
    )

{-| End-to-end tests for the TEA-focused TodoMVC.

Demonstrates the integration of BackendTask data loading (server) with
client-side TEA interactions (no server round-trips for mutations).

Contrast with the original todos example where every mutation goes
through a server action.

View in browser: elm-pages test-view tests/TodoTeaTests.elm

-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as HtmlSelector
import Test.PagesProgram as PagesProgram
import Test.Html.Selector as Selector
import TestApp
import Time


baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withTime (Time.millisToPosix 1000)


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


loginAndLoadTodos : TestApp.ProgramTest -> TestApp.ProgramTest
loginAndLoadTodos =
    PagesProgram.simulateCustom "decrypt" decryptResponse
        >> PagesProgram.simulateCustom "findOrCreateUserAndSession" sessionIdResponse
        >> PagesProgram.simulateCustom "getTodosBySession" todosResponse


startLoggedIn : TestApp.ProgramTest
startLoggedIn =
    TestApp.start "/login?magic=fake-hash" baseSetup
        |> loginAndLoadTodos



-- HELPERS


ensureItemsLeft : Int -> TestApp.ProgramTest -> TestApp.ProgramTest
ensureItemsLeft n =
    PagesProgram.ensureViewHas
        [ Selector.tag "span"
        , Selector.class "todo-count"
        , Selector.containing [ Selector.text (String.fromInt n) ]
        ]


{-| Click the toggle checkbox on a specific todo item.
-}
toggleTodo : String -> TestApp.ProgramTest -> TestApp.ProgramTest
toggleTodo description =
    PagesProgram.withinFind
        [ Selector.tag "li"
        , Selector.containing [ Selector.text description ]
        ]
        (PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ HtmlSelector.class "toggle" ])
            Event.click
        )


{-| Click the toggle-all checkbox.
-}
clickToggleAll : TestApp.ProgramTest -> TestApp.ProgramTest
clickToggleAll =
    PagesProgram.simulateDomEvent
        (\query -> query |> Query.find [ HtmlSelector.class "toggle-all" ])
        Event.click


{-| Click a filter link (All, Active, Completed).
-}
clickFilter : String -> TestApp.ProgramTest -> TestApp.ProgramTest
clickFilter filterName =
    PagesProgram.withinFind
        [ Selector.class "filters" ]
        (PagesProgram.simulateDomEvent
            (\query ->
                query
                    |> Query.find
                        [ HtmlSelector.tag "a"
                        , HtmlSelector.containing [ HtmlSelector.text filterName ]
                        ]
            )
            Event.click
        )



-- TESTS


{-| Login flow: magic link -> redirects to todo list -> items visible.
This exercises the BackendTask data loading part of the story.
-}
fullLoginFlowTest : TestApp.ProgramTest
fullLoginFlowTest =
    startLoggedIn
        |> PagesProgram.ensureBrowserUrl
            (\url ->
                if String.contains "/login" url then
                    Expect.fail ("Should have redirected away from /login, but still at: " ++ url)

                else
                    Expect.pass
            )
        |> PagesProgram.ensureViewHas [ Selector.text "todos" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]
        |> ensureItemsLeft 2


{-| Add a todo: type into the input, press Enter. No server round-trip.
-}
addTodoTest : TestApp.ProgramTest
addTodoTest =
    startLoggedIn
        |> ensureItemsLeft 2
        |> PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ HtmlSelector.class "new-todo" ])
            (Event.input "Buy eggs")
        |> PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ HtmlSelector.class "new-todo" ])
            ( "keydown", Encode.object [ ( "keyCode", Encode.int 13 ) ] )
        |> PagesProgram.ensureViewHas [ Selector.text "Buy eggs" ]
        |> ensureItemsLeft 3


{-| Toggle a todo between complete/incomplete. Pure client-side.
-}
toggleTodoTest : TestApp.ProgramTest
toggleTodoTest =
    startLoggedIn
        |> ensureItemsLeft 2
        |> toggleTodo "Buy milk"
        |> ensureItemsLeft 1
        |> toggleTodo "Buy milk"
        |> ensureItemsLeft 2


{-| Delete a todo. Pure client-side.
-}
deleteTodoTest : TestApp.ProgramTest
deleteTodoTest =
    startLoggedIn
        |> PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
        |> PagesProgram.withinFind
            [ Selector.tag "li"
            , Selector.containing [ Selector.text "Write tests" ]
            ]
            (PagesProgram.clickButtonWith [ Selector.class "destroy" ])
        |> PagesProgram.ensureViewHasNot [ Selector.text "Write tests" ]
        |> ensureItemsLeft 2


{-| Toggle all: marks all items complete (or all incomplete if all are
already complete). Pure client-side.
-}
toggleAllTest : TestApp.ProgramTest
toggleAllTest =
    startLoggedIn
        |> ensureItemsLeft 2
        |> clickToggleAll
        |> ensureItemsLeft 0
        -- All are complete now. Toggle again to make all incomplete.
        |> clickToggleAll
        |> ensureItemsLeft 3


{-| Clear completed: removes all completed items. Pure client-side.
-}
clearCompletedTest : TestApp.ProgramTest
clearCompletedTest =
    startLoggedIn
        |> PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
        |> PagesProgram.clickButton "Clear completed (1)"
        |> PagesProgram.ensureViewHasNot [ Selector.text "Write tests" ]
        |> ensureItemsLeft 2


{-| Filter views: switch between All / Active / Completed.
Client-side state via SetVisibility msg.
-}
filterViewTest : TestApp.ProgramTest
filterViewTest =
    startLoggedIn
        -- All view: all 3 items visible
        |> PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]
        -- Click "Active" filter
        |> clickFilter "Active"
        |> PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
        |> PagesProgram.ensureViewHasNot [ Selector.text "Write tests" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]
        -- Click "Completed" filter
        |> clickFilter "Completed"
        |> PagesProgram.ensureViewHasNot [ Selector.text "Buy milk" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
        |> PagesProgram.ensureViewHasNot [ Selector.text "Walk the dog" ]
        -- Click "All" to go back
        |> clickFilter "All"
        |> PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Write tests" ]
        |> PagesProgram.ensureViewHas [ Selector.text "Walk the dog" ]


{-| Add multiple todos in sequence. Each add is instant (client-side).
-}
addMultipleTodosTest : TestApp.ProgramTest
addMultipleTodosTest =
    startLoggedIn
        |> ensureItemsLeft 2
        |> PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ HtmlSelector.class "new-todo" ])
            (Event.input "First new todo")
        |> PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ HtmlSelector.class "new-todo" ])
            ( "keydown", Encode.object [ ( "keyCode", Encode.int 13 ) ] )
        |> PagesProgram.ensureViewHas [ Selector.text "First new todo" ]
        |> PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ HtmlSelector.class "new-todo" ])
            (Event.input "Second new todo")
        |> PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ HtmlSelector.class "new-todo" ])
            ( "keydown", Encode.object [ ( "keyCode", Encode.int 13 ) ] )
        |> PagesProgram.ensureViewHas [ Selector.text "Second new todo" ]
        |> ensureItemsLeft 4
