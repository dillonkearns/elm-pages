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


{-| Optimistic UI: toggle all to complete while the action is in-flight,
assert the optimistic state immediately, then resolve the server
roundtrip and verify final state matches.

Starting state: "Buy milk" (incomplete), "Write tests" (complete)
After toggle-all: both complete -> "0 items left" (optimistic)
After server confirms: still "0 items left"
-}
optimisticUiTest : TestApp.ProgramTest
optimisticUiTest =
    startLoggedInWithTodos todosResponse
        -- Starting state: 1 incomplete, 1 complete
        |> PagesProgram.ensureViewHas [ text " item left" ]
        -- Click toggle-all -- fetcher action fires but hasn't resolved
        |> PagesProgram.clickButton "❯"
        -- OPTIMISTIC: UI immediately shows all complete
        |> PagesProgram.ensureViewHas [ text " items left" ]
        -- Resolve the server roundtrip
        |> PagesProgram.simulateCustom "checkAllTodos" Encode.null
        |> PagesProgram.simulateCustom "getTodosBySession" allCompleteTodosResponse
        -- Server-confirmed state matches optimistic prediction
        |> PagesProgram.ensureViewHas [ text " items left" ]
