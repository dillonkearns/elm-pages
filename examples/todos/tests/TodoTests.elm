module TodoTests exposing
    ( fullLoginFlowTest
    , preSignedInSessionTest
    , toggleAllTest
    , clearCompletedTest
    , optimisticUiTest
    , createTodoTest
    , editTodoTest
    , filterViewTest
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
import Test.Html.Selector as Selector
import Test.Html.Query as Query
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.Selector as PSelector
import TestApp
import Time



-- SETUP


baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withTime (Time.millisToPosix 1000)


loginActionSetup =
    baseSetup
        |> BackendTaskTest.withEnv "TODOS_SEND_GRID_KEY" "test-send-grid-key"
        |> BackendTaskTest.withEnv "BASE_URL" "https://localhost:1234"


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


finishMagicLinkLoginAndLoadTodos : Encode.Value -> TestApp.ProgramTest -> TestApp.ProgramTest
finishMagicLinkLoginAndLoadTodos todos =
    PagesProgram.simulateCustom "decrypt" decryptResponse
        >> PagesProgram.simulateCustom "findOrCreateUserAndSession" sessionIdResponse
        >> PagesProgram.simulateCustom "getTodosBySession" todos


startAfterMagicLinkWithTodos : Encode.Value -> TestApp.ProgramTest
startAfterMagicLinkWithTodos todos =
    TestApp.start "/login?magic=fake-hash" baseSetup
        |> finishMagicLinkLoginAndLoadTodos todos


startSignedInWithTodos : Encode.Value -> TestApp.ProgramTest
startSignedInWithTodos todos =
    TestApp.start "/"
        (baseSetup
            |> BackendTaskTest.withSessionCookie
                { name = "mysession"
                , session =
                    BackendTaskTest.session
                        |> BackendTaskTest.withSessionValue "sessionId" "test-session-id"
                }
        )
        |> PagesProgram.ensureCustom "getTodosBySession"
        |> PagesProgram.simulateCustom "getTodosBySession" todos



-- USER INTERACTION / ASSERTION HELPERS


{-| Assert the footer shows exactly N items left.
-}
ensureItemsLeft : Int -> TestApp.ProgramTest -> TestApp.ProgramTest
ensureItemsLeft n =
    PagesProgram.withinFind
        [ PSelector.class "todo-count" ]
        (PagesProgram.ensureViewHas [ PSelector.text (String.fromInt n) ])


{-| Click the toggle checkbox on a specific todo item.
-}
toggleTodo : String -> TestApp.ProgramTest -> TestApp.ProgramTest
toggleTodo description =
    PagesProgram.withinFind
        [ PSelector.tag "li"
        , PSelector.containing [ PSelector.value description ]
        ]
        (PagesProgram.clickButtonWith [ PSelector.class "toggle" ])


{-| Click the delete (X) button on a specific todo item.
-}
deleteTodo : String -> TestApp.ProgramTest -> TestApp.ProgramTest
deleteTodo description =
    PagesProgram.withinFind
        [ PSelector.tag "li"
        , PSelector.containing [ PSelector.value description ]
        ]
        (PagesProgram.clickButtonWith [ PSelector.class "destroy" ])


{-| Simulate submitting the form with the given CSS class.

This simulates the browser's form submit event, which is what happens
when a user presses Enter in a text input. Needed for forms that have
no submit button (like the new-todo input and inline edit inputs).
-}
submitFormByClass : String -> TestApp.ProgramTest -> TestApp.ProgramTest
submitFormByClass formClass =
    PagesProgram.simulateDomEvent
        (\query -> query |> Query.find [ Selector.tag "form", Selector.class formClass ])
        ( "submit"
        , Encode.object
            [ ( "currentTarget"
              , Encode.object
                    [ ( "method", Encode.string "POST" )
                    , ( "action", Encode.string "" )
                    , ( "id", Encode.null )
                    ]
              )
            ]
        )



-- TESTS


{-| Full login flow: user sees login page, follows magic link,
gets redirected to the todo list, and sees their items.
-}
fullLoginFlowTest : TestApp.ProgramTest
fullLoginFlowTest =
    TestApp.start "/login" loginActionSetup
        |> PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
        |> PagesProgram.fillIn "login" "email" "user@example.com"
        |> PagesProgram.clickButton "Login"
        |> PagesProgram.ensureCustom "encrypt"
        |> PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash")
        |> PagesProgram.ensureHttpPost "https://api.sendgrid.com/v3/mail/send"
        |> PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
        |> PagesProgram.ensureViewHas [ PSelector.text "Check your inbox for your login link!" ]
        |> PagesProgram.navigateTo "/login?magic=fake-hash"
        |> finishMagicLinkLoginAndLoadTodos todosResponse
        |> PagesProgram.ensureViewHas [ PSelector.text "todos" ]
        |> PagesProgram.ensureBrowserUrl (Expect.equal "https://localhost:1234/")
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Write tests" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Walk the dog" ]
        |> ensureItemsLeft 2


{-| Start with a pre-signed session cookie and go straight to the
authenticated route without exercising the login link flow.
-}
preSignedInSessionTest : TestApp.ProgramTest
preSignedInSessionTest =
    startSignedInWithTodos todosResponse
        |> PagesProgram.ensureBrowserUrl (Expect.equal "https://localhost:1234/")
        |> PagesProgram.ensureViewHas [ PSelector.text "todos" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Write tests" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Walk the dog" ]
        |> ensureItemsLeft 2


{-| Login, toggle all items complete, verify the count drops to 0.
-}
toggleAllTest : TestApp.ProgramTest
toggleAllTest =
    startAfterMagicLinkWithTodos todosResponse
        |> ensureItemsLeft 2
        |> PagesProgram.clickButton "❯"
        |> PagesProgram.simulateCustom "checkAllTodos" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" allCompleteTodosResponse
        |> ensureItemsLeft 0


{-| Login, clear completed items, verify they're removed.
-}
clearCompletedTest : TestApp.ProgramTest
clearCompletedTest =
    startAfterMagicLinkWithTodos todosResponse
        |> ensureItemsLeft 2
        |> PagesProgram.ensureViewHas [ PSelector.value "Write tests" ]
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
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Walk the dog" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.value "Write tests" ]


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
    startAfterMagicLinkWithTodos todosResponse
        |> ensureItemsLeft 2
        |> PagesProgram.group "Rapid-fire user actions"
            (deleteTodo "Write tests"
                >> toggleTodo "Buy milk"
                >> toggleTodo "Walk the dog"
                >> toggleTodo "Buy milk"
            )
        |> PagesProgram.group "Verify optimistic state"
            (PagesProgram.ensureViewHasNot [ PSelector.value "Write tests" ]
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.value "Buy milk" ] ]
                    (PagesProgram.ensureViewHasNot [ PSelector.class "completed" ])
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.value "Walk the dog" ] ]
                    (PagesProgram.ensureViewHas [ PSelector.class "completed" ])
                >> ensureItemsLeft 1
            )
        |> PagesProgram.group "Resolve server responses"
            (PagesProgram.simulateCustom "deleteTodo" Encode.null
                >> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                >> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                >> PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                >> PagesProgram.simulateCustom "getTodosBySession" finalServerState
            )
        |> PagesProgram.group "Verify server-confirmed state"
            (PagesProgram.ensureViewHasNot [ PSelector.value "Write tests" ]
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.value "Buy milk" ] ]
                    (PagesProgram.ensureViewHasNot [ PSelector.class "completed" ])
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.value "Walk the dog" ] ]
                    (PagesProgram.ensureViewHas [ PSelector.class "completed" ])
                >> ensureItemsLeft 1
            )


{-| Create a new todo: type a description in the input, press Enter
(submit the form), the item appears after the server roundtrip.
-}
createTodoTest : TestApp.ProgramTest
createTodoTest =
    startAfterMagicLinkWithTodos todosResponse
        |> ensureItemsLeft 2
        -- Type a new todo description and submit
        |> PagesProgram.fillIn "new-item-0" "description" "Buy eggs"
        |> submitFormByClass "create-form"
        -- Resolve the createTodo action + data reload
        |> PagesProgram.simulateCustom "createTodo" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession"
            (Encode.list identity
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
                , Encode.object
                    [ ( "title", Encode.string "Buy eggs" )
                    , ( "complete", Encode.bool False )
                    , ( "id", Encode.string "todo-4" )
                    ]
                ]
            )
        -- New todo appears, count updated
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy eggs" ]
        |> ensureItemsLeft 3


{-| Edit an existing todo's description inline.
-}
editTodoTest : TestApp.ProgramTest
editTodoTest =
    startAfterMagicLinkWithTodos todosResponse
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
        -- Edit "Buy milk" -> "Buy oat milk"
        |> PagesProgram.fillIn "edit-todo-1" "description" "Buy oat milk"
        |> PagesProgram.simulateDomEvent
            (\query -> query |> Query.find [ Selector.tag "form", Selector.id "edit-todo-1" ])
            ( "submit"
            , Encode.object
                [ ( "currentTarget"
                  , Encode.object
                        [ ( "method", Encode.string "POST" )
                        , ( "action", Encode.string "" )
                        , ( "id", Encode.null )
                        ]
                  )
                ]
            )
        -- Resolve updateTodo action + data reload
        |> PagesProgram.simulateCustom "updateTodo" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession"
            (Encode.list identity
                [ Encode.object
                    [ ( "title", Encode.string "Buy oat milk" )
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
            )
        -- Updated description appears
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy oat milk" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.value "Buy milk" ]


{-| Navigate between All / Active / Completed filter views
and verify the correct items are shown/hidden.
-}
filterViewTest : TestApp.ProgramTest
filterViewTest =
    startAfterMagicLinkWithTodos todosResponse
        -- All view: all 3 items visible
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Write tests" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Walk the dog" ]
        -- Click "Active" filter
        |> PagesProgram.clickLink "Active"
        |> PagesProgram.simulateCustom "getTodosBySession" todosResponse
        -- Active view: only incomplete items
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.value "Write tests" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Walk the dog" ]
        -- Click "Completed" filter
        |> PagesProgram.clickLink "Completed"
        |> PagesProgram.simulateCustom "getTodosBySession" todosResponse
        -- Completed view: only completed items
        |> PagesProgram.ensureViewHasNot [ PSelector.value "Buy milk" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Write tests" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.value "Walk the dog" ]
        -- Click "All" to go back
        |> PagesProgram.clickLink "All"
        |> PagesProgram.simulateCustom "getTodosBySession" todosResponse
        -- All view again: everything visible
        |> PagesProgram.ensureViewHas [ PSelector.value "Buy milk" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Write tests" ]
        |> PagesProgram.ensureViewHas [ PSelector.value "Walk the dog" ]
