module TodoTests exposing
    ( fullLoginFlowTest
    , loginAndRevisitLoginTest
    , logoutAndLoginAsDifferentUserTest
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
import Test.Html.Selector as PSelector
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.CookieJar as CookieJar
import Test.PagesProgram.Session as Session
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
            |> CookieJar.withCookies
                (CookieJar.init
                    |> CookieJar.setSession
                        { name = "mysession"
                        , secret = "test-secret"
                        , session =
                            Session.init
                                |> Session.withValue "sessionId" "test-session-id"
                        }
                )
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
        , PSelector.containing [ PSelector.attribute (Attr.value description) ]
        ]
        (PagesProgram.clickButtonWith [ PSelector.class "toggle" ])


{-| Click the delete (X) button on a specific todo item.
-}
deleteTodo : String -> TestApp.ProgramTest -> TestApp.ProgramTest
deleteTodo description =
    PagesProgram.withinFind
        [ PSelector.tag "li"
        , PSelector.containing [ PSelector.attribute (Attr.value description) ]
        ]
        (PagesProgram.clickButtonWith [ PSelector.class "destroy" ])



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
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
        |> ensureItemsLeft 2


{-| Log in via the magic-link flow, then navigate back to `/login`
while still signed in. Exercises the "already logged in" branch of the
login page and shows the session cookie evolving across multiple steps
(empty → `sessionId` inserted).

Showcases the visual test runner's cookie panel: the `mysession` cookie
picks up two change events (SET on form submit, CHANGED when the magic
link inserts the session id), so the box-pill step selector and
INITIAL / DIFF panels both render meaningfully.
-}
loginAndRevisitLoginTest : TestApp.ProgramTest
loginAndRevisitLoginTest =
    TestApp.start "/login" loginActionSetup
        |> PagesProgram.group "Request a magic link"
            (PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
                >> PagesProgram.fillIn "login" "email" "user@example.com"
                >> PagesProgram.clickButton "Login"
                >> PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash")
                >> PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
                >> PagesProgram.ensureViewHas [ PSelector.text "Check your inbox for your login link!" ]
            )
        |> PagesProgram.group "Follow the magic link"
            (PagesProgram.navigateTo "/login?magic=fake-hash"
                >> finishMagicLinkLoginAndLoadTodos todosResponse
                >> PagesProgram.ensureBrowserUrl (Expect.equal "https://localhost:1234/")
                >> PagesProgram.ensureViewHas [ PSelector.text "todos" ]
                >> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
            )
        |> PagesProgram.group "Revisit the login page while signed in"
            (PagesProgram.navigateTo "/login"
                >> PagesProgram.simulateCustom "getEmailBySessionId" (Encode.string "user@example.com")
                >> PagesProgram.ensureViewHas
                    [ PSelector.text "Hello! You are already logged in as user@example.com" ]
                >> PagesProgram.ensureViewHas [ PSelector.text "Log out" ]
            )


{-| Full auth lifecycle: sign in as one user, log out, then sign in as
a different user and load their todos.

Showcases the cookie view end-to-end: the `mysession` cookie goes
SET → CHANGED (sessionId inserted on magic link) → CHANGED (cleared
on logout) → CHANGED (sessionId re-inserted for the second account).
-}
logoutAndLoginAsDifferentUserTest : TestApp.ProgramTest
logoutAndLoginAsDifferentUserTest =
    let
        aliceTodosResponse =
            Encode.list identity
                [ Encode.object
                    [ ( "title", Encode.string "Call mom" )
                    , ( "complete", Encode.bool False )
                    , ( "id", Encode.string "alice-todo-1" )
                    ]
                , Encode.object
                    [ ( "title", Encode.string "Finish report" )
                    , ( "complete", Encode.bool False )
                    , ( "id", Encode.string "alice-todo-2" )
                    ]
                ]

        aliceDecryptResponse =
            Encode.string "{\"text\":\"alice@example.com\",\"expiresAt\":99999999999999}"
    in
    TestApp.start "/login" loginActionSetup
        |> PagesProgram.group "Log in as user@example.com"
            (PagesProgram.fillIn "login" "email" "user@example.com"
                >> PagesProgram.clickButton "Login"
                >> PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash-user")
                >> PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
                >> PagesProgram.navigateTo "/login?magic=fake-hash-user"
                >> finishMagicLinkLoginAndLoadTodos todosResponse
                >> PagesProgram.ensureViewHas [ PSelector.text "todos" ]
                >> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
            )
        |> PagesProgram.group "Log out"
            (PagesProgram.navigateTo "/login"
                >> PagesProgram.simulateCustom "getEmailBySessionId" (Encode.string "user@example.com")
                >> PagesProgram.ensureViewHas
                    [ PSelector.text "Hello! You are already logged in as user@example.com" ]
                >> PagesProgram.clickButton "Log out"
                >> PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
            )
        |> PagesProgram.group "Log in as alice@example.com"
            (PagesProgram.fillIn "login" "email" "alice@example.com"
                >> PagesProgram.clickButton "Login"
                >> PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash-alice")
                >> PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
                >> PagesProgram.navigateTo "/login?magic=fake-hash-alice"
                >> PagesProgram.simulateCustom "decrypt" aliceDecryptResponse
                >> PagesProgram.simulateCustom "findOrCreateUserAndSession" (Encode.string "alice-session-id")
                >> PagesProgram.simulateCustom "getTodosBySession" aliceTodosResponse
                >> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Call mom") ]
                >> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Finish report") ]
                >> PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Buy milk") ]
            )


{-| Start with a pre-signed session cookie and go straight to the
authenticated route without exercising the login link flow.
-}
preSignedInSessionTest : TestApp.ProgramTest
preSignedInSessionTest =
    startSignedInWithTodos todosResponse
        |> PagesProgram.ensureBrowserUrl (Expect.equal "https://localhost:1234/")
        |> PagesProgram.ensureViewHas [ PSelector.text "todos" ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
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
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
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
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
        |> PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]


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
            (PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ] ]
                    (PagesProgram.ensureViewHasNot [ PSelector.class "completed" ])
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Walk the dog") ] ]
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
            (PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ] ]
                    (PagesProgram.ensureViewHasNot [ PSelector.class "completed" ])
                >> PagesProgram.withinFind
                    [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Walk the dog") ] ]
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
        |> PagesProgram.pressEnter [ PSelector.class "new-todo" ]
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
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy eggs") ]
        |> ensureItemsLeft 3


{-| Edit an existing todo's description inline.
-}
editTodoTest : TestApp.ProgramTest
editTodoTest =
    startAfterMagicLinkWithTodos todosResponse
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
        -- Edit "Buy milk" -> "Buy oat milk"
        |> PagesProgram.fillIn "edit-todo-1" "description" "Buy oat milk"
        |> PagesProgram.pressEnter [ PSelector.class "edit-input" ]
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
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy oat milk") ]
        |> PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Buy milk") ]


{-| Navigate between All / Active / Completed filter views
and verify the correct items are shown/hidden.
-}
filterViewTest : TestApp.ProgramTest
filterViewTest =
    startAfterMagicLinkWithTodos todosResponse
        -- All view: all 3 items visible
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
        -- Click "Active" filter
        |> PagesProgram.clickLink "Active"
        |> PagesProgram.simulateCustom "getTodosBySession" todosResponse
        -- Active view: only incomplete items
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
        -- Click "Completed" filter
        |> PagesProgram.clickLink "Completed"
        |> PagesProgram.simulateCustom "getTodosBySession" todosResponse
        -- Completed view: only completed items
        |> PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Walk the dog") ]
        -- Click "All" to go back
        |> PagesProgram.clickLink "All"
        |> PagesProgram.simulateCustom "getTodosBySession" todosResponse
        -- All view again: everything visible
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
        |> PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
