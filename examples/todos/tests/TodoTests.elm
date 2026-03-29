module TodoTests exposing
    ( fullLoginFlowTest
    , toggleAllTest
    , clearCompletedTest
    , optimisticUiTest
    )

{-| End-to-end test flows for the Todos full-stack example.

Each test exercises a full user journey: arriving unauthenticated,
logging in via magic link, interacting with the todo list, and
verifying the resulting state.

View in browser: elm-pages test-view tests/TodoTests.elm

-}

import Expect
import Html.Attributes as Attr
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as Selector exposing (attribute, class, tag, text)
import Test.Html.Query as Query
import Test.PagesProgram as PagesProgram
import TestApp
import Time



-- SETUP


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
            , ( "id", Encode.string "todo-1" )
            ]
        , Encode.object
            [ ( "title", Encode.string "Write tests" )
            , ( "complete", Encode.bool True )
            , ( "id", Encode.string "todo-2" )
            ]
        , Encode.object
            [ ( "title", Encode.string "Walk the dog" )
            , ( "complete", Encode.bool False )
            , ( "id", Encode.string "todo-3" )
            ]
        ]


allCompleteTodosResponse : Encode.Value
allCompleteTodosResponse =
    Encode.list identity
        [ Encode.object
            [ ( "title", Encode.string "Buy milk" )
            , ( "complete", Encode.bool True )
            , ( "id", Encode.string "todo-1" )
            ]
        , Encode.object
            [ ( "title", Encode.string "Write tests" )
            , ( "complete", Encode.bool True )
            , ( "id", Encode.string "todo-2" )
            ]
        , Encode.object
            [ ( "title", Encode.string "Walk the dog" )
            , ( "complete", Encode.bool True )
            , ( "id", Encode.string "todo-3" )
            ]
        ]


loginAndLoadTodos : Encode.Value -> TestApp.ProgramTest -> TestApp.ProgramTest
loginAndLoadTodos todos =
    PagesProgram.simulateCustom "decrypt" decryptResponse
        >> PagesProgram.simulateCustom "findOrCreateUserAndSession" sessionIdResponse
        >> PagesProgram.simulateCustom "getTodosBySession" todos


startLoggedInWithTodos : Encode.Value -> TestApp.ProgramTest
startLoggedInWithTodos todos =
    TestApp.start "/login?magic=fake-hash" baseSetup
        |> loginAndLoadTodos todos



-- USER INTERACTION / ASSERTION HELPERS


{-| Assert the footer shows exactly N items left.
-}
ensureItemsLeft : Int -> TestApp.ProgramTest -> TestApp.ProgramTest
ensureItemsLeft n =
    PagesProgram.within
        (Query.find [ class "todo-count" ])
        (PagesProgram.ensureViewHas [ text (String.fromInt n) ])


{-| Click the toggle checkbox on a specific todo item.
-}
toggleTodo : String -> TestApp.ProgramTest -> TestApp.ProgramTest
toggleTodo description =
    PagesProgram.within
        (Query.find
            [ tag "li"
            , Selector.containing [ attribute (Attr.value description) ]
            ]
        )
        (PagesProgram.clickButtonWith [ class "toggle" ])


{-| Click the delete (X) button on a specific todo item.
-}
deleteTodo : String -> TestApp.ProgramTest -> TestApp.ProgramTest
deleteTodo description =
    PagesProgram.within
        (Query.find
            [ tag "li"
            , Selector.containing [ attribute (Attr.value description) ]
            ]
        )
        (PagesProgram.clickButtonWith [ class "destroy" ])



-- TESTS


{-| Full login flow: user sees login page, follows magic link,
gets redirected to the todo list, and sees their items.
-}
fullLoginFlowTest : TestApp.ProgramTest
fullLoginFlowTest =
    -- First verify the unauthenticated login page renders
    TestApp.start "/login" baseSetup
        |> PagesProgram.ensureViewHas [ text "You aren't logged in yet." ]
        |> PagesProgram.done
    -- Then exercise the full magic link login flow
    |> always
        (startLoggedInWithTodos todosResponse
            |> PagesProgram.ensureBrowserUrl
                (\url ->
                    if String.contains "/login" url then
                        Expect.fail ("Should have redirected away from /login, but still at: " ++ url)

                    else
                        Expect.pass
                )
            |> PagesProgram.ensureViewHas [ text "todos" ]
            |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
            |> PagesProgram.ensureViewHas [ attribute (Attr.value "Write tests") ]
            |> PagesProgram.ensureViewHas [ attribute (Attr.value "Walk the dog") ]
            |> ensureItemsLeft 2
        )


{-| Login, toggle all items complete, verify the count drops to 0.
-}
toggleAllTest : TestApp.ProgramTest
toggleAllTest =
    startLoggedInWithTodos todosResponse
        |> ensureItemsLeft 2
        |> PagesProgram.clickButton "❯"
        |> PagesProgram.simulateCustom "checkAllTodos" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" allCompleteTodosResponse
        |> ensureItemsLeft 0


{-| Login, clear completed items, verify they're removed.
-}
clearCompletedTest : TestApp.ProgramTest
clearCompletedTest =
    startLoggedInWithTodos todosResponse
        |> ensureItemsLeft 2
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Write tests") ]
        |> PagesProgram.clickButton "Clear completed"
        |> PagesProgram.simulateCustom "clearCompletedTodos" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession"
            (Encode.list identity
                [ Encode.object
                    [ ( "title", Encode.string "Buy milk" )
                    , ( "complete", Encode.bool False )
                    , ( "id", Encode.string "todo-1" )
                    ]
                , Encode.object
                    [ ( "title", Encode.string "Walk the dog" )
                    , ( "complete", Encode.bool False )
                    , ( "id", Encode.string "todo-3" )
                    ]
                ]
            )
        |> ensureItemsLeft 2
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Walk the dog") ]
        |> PagesProgram.ensureViewHasNot [ attribute (Attr.value "Write tests") ]


{-| Optimistic UI: fire off several concurrent user actions while
server roundtrips are still in-flight, assert the optimistic view
state, resolve everything, verify the final state matches.

Starting state:
  - "Buy milk" (incomplete)
  - "Write tests" (complete)
  - "Walk the dog" (incomplete)
  -> 2 items left

User actions (all before any server response):
  1. Delete "Write tests"
  2. Toggle "Buy milk" to complete
  3. Toggle "Walk the dog" to complete
  4. Toggle "Buy milk" back to incomplete (changed mind)

Expected optimistic state:
  - "Write tests" gone, "Buy milk" incomplete, "Walk the dog" complete
  -> 1 item left
-}
optimisticUiTest : TestApp.ProgramTest
optimisticUiTest =
    let
        finalServerState =
            Encode.list identity
                [ Encode.object
                    [ ( "title", Encode.string "Buy milk" )
                    , ( "complete", Encode.bool False )
                    , ( "id", Encode.string "todo-1" )
                    ]
                , Encode.object
                    [ ( "title", Encode.string "Walk the dog" )
                    , ( "complete", Encode.bool True )
                    , ( "id", Encode.string "todo-3" )
                    ]
                ]
    in
    startLoggedInWithTodos todosResponse
        |> ensureItemsLeft 2
        ---------------------------------------------------------------
        -- Rapid-fire user actions, no server responses yet
        ---------------------------------------------------------------
        |> deleteTodo "Write tests"
        |> toggleTodo "Buy milk"
        |> toggleTodo "Walk the dog"
        |> toggleTodo "Buy milk"
        ---------------------------------------------------------------
        -- Assert optimistic state while everything is still in-flight
        ---------------------------------------------------------------
        |> PagesProgram.ensureViewHasNot [ attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Walk the dog") ]
        |> ensureItemsLeft 1
        ---------------------------------------------------------------
        -- Resolve all in-flight actions + data reloads
        ---------------------------------------------------------------
        |> PagesProgram.simulateCustom "deleteTodo" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" finalServerState
        |> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" finalServerState
        |> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" finalServerState
        |> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" finalServerState
        ---------------------------------------------------------------
        -- Server-confirmed state matches optimistic prediction
        ---------------------------------------------------------------
        |> PagesProgram.ensureViewHasNot [ attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Walk the dog") ]
        |> ensureItemsLeft 1
