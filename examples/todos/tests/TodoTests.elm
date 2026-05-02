module TodoTests exposing (suite)

{-| End-to-end test flows for the Todos full-stack example.

Each test exercises a full user journey: arriving unauthenticated,
logging in via magic link, interacting with the todo list, and
verifying the resulting state.

View in browser: elm-pages dev, then open /\_tests

-}

import Expect
import Html.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as PSelector
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.CookieJar as CookieJar
import Test.PagesProgram.Session as Session
import TestApp
import Time


suite : PagesProgram.Test
suite =
    PagesProgram.describe "Todos full-stack example"
        [ PagesProgram.describe "Auth flows"
            [ PagesProgram.test "completes the magic-link login flow"
                (TestApp.start "/login" loginActionSetup)
                [ PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
                , PagesProgram.fillIn "login" "email" "user@example.com"
                , PagesProgram.clickButton "Login"
                , PagesProgram.ensureCustom "encrypt" (\_ -> Expect.pass)
                , PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash")
                , PagesProgram.ensureHttpPost "https://api.sendgrid.com/v3/mail/send" (\_ -> Expect.pass)
                , PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
                , PagesProgram.ensureViewHas [ PSelector.text "Check your inbox for your login link!" ]
                , PagesProgram.navigateTo "/login?magic=fake-hash"
                , finishMagicLinkLoginAndLoadTodos todosResponse
                , PagesProgram.ensureViewHas [ PSelector.text "todos" ]
                , PagesProgram.ensureBrowserUrl (Expect.equal "https://localhost:1234/")
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
                , ensureItemsLeft 2
                ]
            , PagesProgram.test "shows the already-signed-in branch when revisiting /login"
                (TestApp.start "/login" loginActionSetup)
                [ PagesProgram.group "Request a magic link"
                    [ PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
                    , PagesProgram.fillIn "login" "email" "user@example.com"
                    , PagesProgram.clickButton "Login"
                    , PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash")
                    , PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
                    , PagesProgram.ensureViewHas [ PSelector.text "Check your inbox for your login link!" ]
                    ]
                , PagesProgram.group "Follow the magic link"
                    [ PagesProgram.navigateTo "/login?magic=fake-hash"
                    , finishMagicLinkLoginAndLoadTodos todosResponse
                    , PagesProgram.ensureBrowserUrl (Expect.equal "https://localhost:1234/")
                    , PagesProgram.ensureViewHas [ PSelector.text "todos" ]
                    , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                    ]
                , PagesProgram.group "Revisit the login page while signed in"
                    [ PagesProgram.navigateTo "/login"
                    , PagesProgram.simulateCustom "getEmailBySessionId" (Encode.string "user@example.com")
                    , PagesProgram.ensureViewHas
                        [ PSelector.text "Hello! You are already logged in as user@example.com" ]
                    , PagesProgram.ensureViewHas [ PSelector.text "Log out" ]
                    ]
                ]
            , PagesProgram.test "logs out and signs in as a different user"
                (TestApp.start "/login" loginActionSetup)
                [ PagesProgram.group "Log in as user@example.com"
                    [ PagesProgram.fillIn "login" "email" "user@example.com"
                    , PagesProgram.clickButton "Login"
                    , PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash-user")
                    , PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
                    , PagesProgram.navigateTo "/login?magic=fake-hash-user"
                    , finishMagicLinkLoginAndLoadTodos todosResponse
                    , PagesProgram.ensureViewHas [ PSelector.text "todos" ]
                    , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                    ]
                , PagesProgram.group "Log out"
                    [ PagesProgram.navigateTo "/login"
                    , PagesProgram.simulateCustom "getEmailBySessionId" (Encode.string "user@example.com")
                    , PagesProgram.ensureViewHas
                        [ PSelector.text "Hello! You are already logged in as user@example.com" ]
                    , PagesProgram.clickButton "Log out"
                    , PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
                    ]
                , PagesProgram.group "Log in as alice@example.com"
                    [ PagesProgram.fillIn "login" "email" "alice@example.com"
                    , PagesProgram.clickButton "Login"
                    , PagesProgram.simulateCustom "encrypt" (Encode.string "fake-hash-alice")
                    , PagesProgram.simulateHttpPost "https://api.sendgrid.com/v3/mail/send" Encode.null
                    , PagesProgram.navigateTo "/login?magic=fake-hash-alice"
                    , PagesProgram.simulateCustom "decrypt"
                        (Encode.string "{\"text\":\"alice@example.com\",\"expiresAt\":99999999999999}")
                    , PagesProgram.simulateCustom "findOrCreateUserAndSession" (Encode.string "alice-session-id")
                    , PagesProgram.simulateCustom "getTodosBySession" aliceTodosResponse
                    , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Call mom") ]
                    , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Finish report") ]
                    , PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Buy milk") ]
                    ]
                ]
            , PagesProgram.test "loads with a pre-signed session cookie"
                (startSignedInWithTodos todosResponse)
                [ PagesProgram.ensureCustom "getTodosBySession" (\_ -> Expect.pass)
                , PagesProgram.simulateCustom "getTodosBySession" todosResponse
                , PagesProgram.ensureBrowserUrl (Expect.equal "https://localhost:1234/")
                , PagesProgram.ensureViewHas [ PSelector.text "todos" ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
                , ensureItemsLeft 2
                ]
            ]
        , PagesProgram.describe "Todo management"
            [ PagesProgram.test "creates a new todo via Enter"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , ensureItemsLeft 2
                , PagesProgram.fillIn "new-item-0" "description" "Buy eggs"
                , PagesProgram.pressEnter [ PSelector.class "new-todo" ]
                , PagesProgram.simulateCustom "createTodo" Encode.null
                , PagesProgram.simulateCustom "getTodosBySession"
                    (Encode.list identity
                        [ todoFixture "Buy milk" False "todo-1"
                        , todoFixture "Write tests" True "todo-2"
                        , todoFixture "Walk the dog" False "todo-3"
                        , todoFixture "Buy eggs" False "todo-4"
                        ]
                    )
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy eggs") ]
                , ensureItemsLeft 3
                ]
            , PagesProgram.test "edits an existing todo inline"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.fillIn "edit-todo-1" "description" "Buy oat milk"
                , PagesProgram.pressEnter [ PSelector.id "todo-todo-1" ]
                , PagesProgram.simulateCustom "updateTodo" Encode.null
                , PagesProgram.simulateCustom "getTodosBySession"
                    (Encode.list identity
                        [ todoFixture "Buy oat milk" False "todo-1"
                        , todoFixture "Write tests" True "todo-2"
                        , todoFixture "Walk the dog" False "todo-3"
                        ]
                    )
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy oat milk") ]
                , PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Buy milk") ]
                ]
            , PagesProgram.test "toggles all todos complete"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , ensureItemsLeft 2
                , PagesProgram.clickButton "❯"
                , PagesProgram.simulateCustom "checkAllTodos" Encode.null
                , PagesProgram.simulateCustom "getTodosBySession" allCompleteTodosResponse
                , ensureItemsLeft 0
                ]
            , PagesProgram.test "clears completed todos"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , ensureItemsLeft 2
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
                , PagesProgram.clickButton "Clear completed"
                , PagesProgram.simulateCustom "clearCompletedTodos" Encode.null
                , PagesProgram.simulateCustom "getTodosBySession"
                    (Encode.list identity
                        [ todoFixture "Buy milk" False "todo-1"
                        , todoFixture "Walk the dog" False "todo-3"
                        ]
                    )
                , ensureItemsLeft 2
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
                , PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]
                ]
            , PagesProgram.test "renders optimistic state during concurrent fetchers"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , ensureItemsLeft 2
                , PagesProgram.group "Rapid-fire user actions"
                    [ deleteTodo "Write tests"
                    , toggleTodo "Buy milk"
                    , toggleTodo "Walk the dog"
                    , toggleTodo "Buy milk"
                    ]
                , PagesProgram.group "Verify optimistic state"
                    [ PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ] ]
                        [ PagesProgram.ensureViewHasNot [ PSelector.class "completed" ] ]
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Walk the dog") ] ]
                        [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
                    , ensureItemsLeft 1
                    ]
                , PagesProgram.group "Resolve server responses"
                    [ PagesProgram.simulateCustom "deleteTodo" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "getTodosBySession"
                        (Encode.list identity
                            [ todoFixture "Buy milk" False "todo-1"
                            , todoFixture "Walk the dog" True "todo-3"
                            ]
                        )
                    ]
                , PagesProgram.group "Verify server-confirmed state"
                    [ PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ] ]
                        [ PagesProgram.ensureViewHasNot [ PSelector.class "completed" ] ]
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Walk the dog") ] ]
                        [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
                    , ensureItemsLeft 1
                    ]
                ]
            , PagesProgram.test "repeats toggles on a single item"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , ensureItemsLeft 2
                , PagesProgram.group "Toggle todo 3x (optimistic)"
                    [ toggleTodo "Buy milk"
                    , ensureItemsLeft 1
                    , toggleTodo "Buy milk"
                    , ensureItemsLeft 2
                    , toggleTodo "Buy milk"
                    , ensureItemsLeft 1
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ] ]
                        [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
                    ]
                , PagesProgram.group "Resolve three fetchers + reload"
                    [ simulateToggle { todoId = "todo-1", complete = True }
                    , simulateToggle { todoId = "todo-1", complete = False }
                    , simulateToggle { todoId = "todo-1", complete = True }
                    , PagesProgram.simulateCustom "getTodosBySession"
                        (Encode.list identity
                            [ todoFixture "Buy milk" True "todo-1"
                            , todoFixture "Write tests" True "todo-2"
                            , todoFixture "Walk the dog" False "todo-3"
                            ]
                        )
                    , ensureItemsLeft 1
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ] ]
                        [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
                    ]
                ]
            , PagesProgram.test "stress-tests stacked toggle fetchers per item"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , ensureItemsLeft 2
                , PagesProgram.group "Toggle storm: 6 concurrent fetchers"
                    [ toggleTodo "Buy milk"
                    , ensureItemsLeft 1
                    , toggleTodo "Write tests"
                    , ensureItemsLeft 2
                    , toggleTodo "Buy milk"
                    , ensureItemsLeft 3
                    , toggleTodo "Walk the dog"
                    , ensureItemsLeft 2
                    , toggleTodo "Write tests"
                    , ensureItemsLeft 1
                    , toggleTodo "Buy milk"
                    , ensureItemsLeft 0
                    ]
                , PagesProgram.group "Verify optimistic state (latest target per item)"
                    [ PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ] ]
                        [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Write tests") ] ]
                        [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
                    , PagesProgram.withinFind
                        [ PSelector.tag "li", PSelector.containing [ PSelector.attribute (Attr.value "Walk the dog") ] ]
                        [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
                    ]
                , PagesProgram.group "Resolve all six fetchers + reload"
                    [ PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "setTodoCompletion" Encode.null
                    , PagesProgram.simulateCustom "getTodosBySession"
                        (Encode.list identity
                            [ todoFixture "Buy milk" True "todo-1"
                            , todoFixture "Write tests" True "todo-2"
                            , todoFixture "Walk the dog" True "todo-3"
                            ]
                        )

                ,  ensureItemsLeft 0
                    , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                    , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
                    , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
                    ]
                ]
            ]
        , PagesProgram.describe "Filtering"
            [ PagesProgram.test "switches All / Active / Completed filter views"
                startAfterMagicLink
                [ finishMagicLinkLoginAndLoadTodos todosResponse
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
                , PagesProgram.clickLink "Active"
                , PagesProgram.simulateCustom "getTodosBySession" todosResponse
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Write tests") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
                , PagesProgram.clickLink "Completed"
                , PagesProgram.simulateCustom "getTodosBySession" todosResponse
                , PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
                , PagesProgram.ensureViewHasNot [ PSelector.attribute (Attr.value "Walk the dog") ]
                , PagesProgram.clickLink "All"
                , PagesProgram.simulateCustom "getTodosBySession" todosResponse
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Buy milk") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Write tests") ]
                , PagesProgram.ensureViewHas [ PSelector.attribute (Attr.value "Walk the dog") ]
                ]
            ]
        ]



-- SETUP


baseSetup : BackendTaskTest.TestSetup
baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withTime (Time.millisToPosix 1000)


loginActionSetup : BackendTaskTest.TestSetup
loginActionSetup =
    baseSetup
        |> BackendTaskTest.withEnv "TODOS_SEND_GRID_KEY" "test-send-grid-key"
        |> BackendTaskTest.withEnv "BASE_URL" "https://localhost:1234"


startAfterMagicLink : TestApp.ProgramTest
startAfterMagicLink =
    TestApp.start "/login?magic=fake-hash" baseSetup


startSignedInWithTodos : Encode.Value -> TestApp.ProgramTest
startSignedInWithTodos _ =
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


finishMagicLinkLoginAndLoadTodos : Encode.Value -> TestApp.Step
finishMagicLinkLoginAndLoadTodos todos =
    PagesProgram.group "Login"
        [ PagesProgram.simulateCustom "decrypt" decryptResponse
        , PagesProgram.simulateCustom "findOrCreateUserAndSession" sessionIdResponse
        , PagesProgram.simulateCustom "getTodosBySession" todos
        ]



-- HELPERS


ensureItemsLeft : Int -> TestApp.Step
ensureItemsLeft n =
    PagesProgram.withinFind
        [ PSelector.class "todo-count" ]
        [ PagesProgram.ensureViewHas [ PSelector.text (String.fromInt n) ] ]


toggleTodo : String -> TestApp.Step
toggleTodo description =
    PagesProgram.withinFind
        [ PSelector.tag "li"
        , PSelector.containing [ PSelector.attribute (Attr.value description) ]
        ]
        [ PagesProgram.clickButtonWith [ PSelector.class "toggle" ] ]


deleteTodo : String -> TestApp.Step
deleteTodo description =
    PagesProgram.withinFind
        [ PSelector.tag "li"
        , PSelector.containing [ PSelector.attribute (Attr.value description) ]
        ]
        [ PagesProgram.clickButtonWith [ PSelector.class "destroy" ] ]


simulateToggle : { todoId : String, complete : Bool } -> TestApp.Step
simulateToggle expected =
    PagesProgram.simulateCustomWith "setTodoCompletion"
        (\args ->
            Decode.decodeValue
                (Decode.map2 (\tid c -> { todoId = tid, complete = c })
                    (Decode.field "todoId" Decode.string)
                    (Decode.field "complete" Decode.bool)
                )
                args
                |> Expect.equal (Ok expected)
        )
        Encode.null



-- RESPONSE FIXTURES


decryptResponse : Encode.Value
decryptResponse =
    Encode.string "{\"text\":\"user@example.com\",\"expiresAt\":99999999999999}"


sessionIdResponse : Encode.Value
sessionIdResponse =
    Encode.string "test-session-id"


todoFixture : String -> Bool -> String -> Encode.Value
todoFixture title complete id =
    Encode.object
        [ ( "title", Encode.string title )
        , ( "complete", Encode.bool complete )
        , ( "id", Encode.string id )
        ]


todosResponse : Encode.Value
todosResponse =
    Encode.list identity
        [ todoFixture "Buy milk" False "todo-1"
        , todoFixture "Write tests" True "todo-2"
        , todoFixture "Walk the dog" False "todo-3"
        ]


allCompleteTodosResponse : Encode.Value
allCompleteTodosResponse =
    Encode.list identity
        [ todoFixture "Buy milk" True "todo-1"
        , todoFixture "Write tests" True "todo-2"
        , todoFixture "Walk the dog" True "todo-3"
        ]


aliceTodosResponse : Encode.Value
aliceTodosResponse =
    Encode.list identity
        [ todoFixture "Call mom" False "alice-todo-1"
        , todoFixture "Finish report" False "alice-todo-2"
        ]
