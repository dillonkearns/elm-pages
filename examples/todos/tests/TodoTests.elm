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
import Test.Html.Selector exposing (attribute, class, text)
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
            |> PagesProgram.ensureViewHas [ text " item left" ]
        )


{-| Login, toggle all items complete, verify the result.
-}
toggleAllTest : TestApp.ProgramTest
toggleAllTest =
    startLoggedInWithTodos todosResponse
        |> PagesProgram.ensureViewHas [ text " item left" ]
        |> PagesProgram.clickButton "❯"
        |> PagesProgram.simulateCustom "checkAllTodos" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" allCompleteTodosResponse
        |> PagesProgram.ensureViewHas [ text " items left" ]


{-| Login, clear completed items, verify they're removed.
-}
clearCompletedTest : TestApp.ProgramTest
clearCompletedTest =
    startLoggedInWithTodos todosResponse
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
                ]
            )
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHasNot [ attribute (Attr.value "Write tests") ]


{-| Optimistic UI stress test: fire off several concurrent mutations
while actions are still in-flight, assert the optimistic view state
immediately, then resolve all BackendTasks and verify final state
matches what the optimistic UI predicted.

Starting state: "Buy milk" (incomplete), "Write tests" (complete)

Mutations (all fired before any server response):

  1. Delete "Write tests" (must happen before any toggle on this
     item, since toggling sets isSaving which hides the delete button)
  2. Toggle "Buy milk" to complete
  3. Toggle "Buy milk" back to incomplete (net effect: no change)

Expected optimistic state:
  - Only "Buy milk" (incomplete) remains, "Write tests" is gone
  - "1 item left"

Then resolve all actions + data reloads and verify the
server-confirmed state matches what the optimistic UI showed.
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
                ]
    in
    startLoggedInWithTodos todosResponse
        -- Starting state: Buy milk (incomplete), Write tests (complete)
        |> PagesProgram.ensureViewHas [ text " item left" ]
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Write tests") ]
        ---------------------------------------------------------------
        -- Fire off several concurrent mutations, no server responses yet
        ---------------------------------------------------------------
        -- 1) Delete "Write tests"
        |> PagesProgram.submitFetcher "delete-todo-2"
        -- 2) Toggle "Buy milk" to complete
        |> PagesProgram.submitFetcher "toggle-todo-1"
        -- 3) Toggle "Buy milk" back to incomplete (changed mind)
        |> PagesProgram.submitFetcher "toggle-todo-1"
        ---------------------------------------------------------------
        -- Assert optimistic state while actions are all still in-flight
        ---------------------------------------------------------------
        -- "Write tests" is optimistically removed
        |> PagesProgram.ensureViewHasNot [ attribute (Attr.value "Write tests") ]
        -- "Buy milk" is still present and incomplete (toggle + untoggle = no change)
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ text " item left" ]
        ---------------------------------------------------------------
        -- Now resolve all in-flight actions + their data reloads
        ---------------------------------------------------------------
        |> PagesProgram.simulateCustom "deleteTodo" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" finalServerState
        |> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" finalServerState
        |> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" finalServerState
        ---------------------------------------------------------------
        -- Server-confirmed state matches what the optimistic UI showed
        ---------------------------------------------------------------
        |> PagesProgram.ensureViewHas [ attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHasNot [ attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ text " item left" ]
