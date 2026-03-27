module TodoTests exposing
    ( loginPageRendersTest
    , magicLinkLoginTest
    , todoListRendersTest
    , toggleAllTest
    , clearCompletedTest
    )

{-| Test suite for the Todos full-stack example.

Showcases testing of:

  - Server-rendered routes with BackendTask.Custom
  - Magic link authentication via encrypted cookies
  - Session management across page transitions
  - Form submissions (toggle all, clear completed)
  - Optimistic UI state

View in browser: elm-pages test-view tests/TodoTests.elm

-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp
import Time



-- SETUP


{-| Base test setup with required environment variables and time.
-}
baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withTime (Time.millisToPosix 1000)


{-| Simulate a BackendTask.Custom.run response.

BackendTask.Custom.run is implemented as an HTTP GET to "elm-pages-internal://port",
so we can use simulateHttpGet to provide responses.
-}
simulateCustom : Encode.Value -> TestApp.ProgramTest -> TestApp.ProgramTest
simulateCustom response =
    PagesProgram.simulateHttpGet "elm-pages-internal://port" response


{-| Response for BackendTask.Custom.run "decrypt".

The decrypt function returns a JSON string. The decoder
then parses this string as JSON containing { text, expiresAt }.
-}
decryptResponse : Encode.Value
decryptResponse =
    Encode.string "{\"text\":\"user@example.com\",\"expiresAt\":99999999999999}"


{-| Response for BackendTask.Custom.run "findOrCreateUserAndSession".

Returns a session ID string.
-}
sessionIdResponse : Encode.Value
sessionIdResponse =
    Encode.string "test-session-id"


{-| Sample todo items as the getTodosBySession response.
-}
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


emptyTodosResponse : Encode.Value
emptyTodosResponse =
    Encode.list identity []


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


{-| Simulate the magic link login flow: decrypt + findOrCreateUserAndSession.
-}
simulateLogin =
    simulateCustom decryptResponse
        >> simulateCustom sessionIdResponse


{-| Full login + data load chain for getting to the todo list.
-}
loginAndLoadTodos : Encode.Value -> TestApp.ProgramTest -> TestApp.ProgramTest
loginAndLoadTodos todos =
    simulateLogin >> simulateCustom todos



-- TESTS


{-| 1. Login page renders correctly without any session.
No HTTP or custom backend task simulation needed.
-}
loginPageRendersTest : TestApp.ProgramTest
loginPageRendersTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.ensureViewHas [ text "You aren't logged in yet." ]


{-| 2. Magic link login redirects to the todo list.

Navigate to /login?magic=... which triggers:
  - decrypt (custom port)
  - findOrCreateUserAndSession (custom port)
  - redirect to todo list
  - getTodosBySession (custom port)
-}
magicLinkLoginTest : TestApp.ProgramTest
magicLinkLoginTest =
    TestApp.start "/login?magic=fake-hash" baseSetup
        |> loginAndLoadTodos todosResponse
        |> PagesProgram.ensureBrowserUrl
            (\url ->
                if String.contains "/login" url then
                    Expect.fail ("Should have redirected away from /login, but still at: " ++ url)

                else
                    Expect.pass
            )


{-| 3. Todo list shows items from the server.
-}
todoListRendersTest : TestApp.ProgramTest
todoListRendersTest =
    TestApp.start "/login?magic=fake-hash" baseSetup
        |> loginAndLoadTodos todosResponse
        |> PagesProgram.ensureViewHas [ text "Buy milk" ]
        |> PagesProgram.ensureViewHas [ text "Write tests" ]
        |> PagesProgram.ensureViewHas [ text "1 item left" ]


{-| 4. Toggle all: click the toggle-all button to mark all complete.

After clicking, the action runs checkAllTodos, then data reloads.
-}
toggleAllTest : TestApp.ProgramTest
toggleAllTest =
    TestApp.start "/login?magic=fake-hash" baseSetup
        |> loginAndLoadTodos todosResponse
        |> PagesProgram.ensureViewHas [ text "1 item left" ]
        -- Click the toggle-all button (text is "❯")
        |> PagesProgram.clickButton "❯"
        -- Action: checkAllTodos custom backend task
        |> simulateCustom Encode.null
        -- Data reload: getTodosBySession returns all complete
        |> simulateCustom allCompleteTodosResponse
        |> PagesProgram.ensureViewHas [ text "0 items left" ]


{-| 5. Clear completed: removes completed todos.
-}
clearCompletedTest : TestApp.ProgramTest
clearCompletedTest =
    TestApp.start "/login?magic=fake-hash" baseSetup
        |> loginAndLoadTodos todosResponse
        |> PagesProgram.ensureViewHas [ text "Clear completed (1)" ]
        -- Click "Clear completed (1)" button
        |> PagesProgram.clickButton "Clear completed (1)"
        -- Action: clearCompletedTodos custom backend task
        |> simulateCustom Encode.null
        -- Data reload: getTodosBySession returns only incomplete todos
        |> simulateCustom
            (Encode.list identity
                [ Encode.object
                    [ ( "title", Encode.string "Buy milk" )
                    , ( "complete", Encode.bool False )
                    , ( "id", Encode.string "todo-1" )
                    ]
                ]
            )
        |> PagesProgram.ensureViewHas [ text "1 item left" ]
        |> PagesProgram.ensureViewHasNot [ text "Write tests" ]
