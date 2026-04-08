module ViewerExample exposing (main)

{-| A standalone example of the Elm visual runner UI.

For the full page-preview experience, use `elm-pages test-view`, which
generates the HTML shell that syncs snapshots into the preview iframe.
Compiling this module directly is still useful for iterating on the Elm app
itself, but it does not include that outer shell.

-}

import BackendTask
import BackendTask.Http
import Blog
import Html
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.Selector as PSelector
import Test.PagesProgram.Viewer as Viewer


main : Program Viewer.Flags Viewer.Model Viewer.Msg
main =
    Viewer.app
        [ ( "Blog: full user journey"
          , blogFullJourney |> PagesProgram.toSnapshots
          )
        , ( "Login flow"
          , loginFlowTest |> PagesProgram.toSnapshots
          )
        , ( "Todo app"
          , todoAppTest |> PagesProgram.toSnapshots
          )
        , ( "Blog: loads posts from API"
          , blogLoadsPostsTest |> PagesProgram.toSnapshots
          )
        , ( "Counter with model inspector"
          , counterTest |> PagesProgram.toSnapshots
          )
        , ( "Search with filtering"
          , searchTest |> PagesProgram.toSnapshots
          )
        ]



-- SAMPLE DATA


samplePosts : Encode.Value
samplePosts =
    Encode.list identity
        [ post "Getting Started with Elm" "Dillon Kearns" "Learn how to build web apps with Elm, the delightful language for reliable web applications."
        , post "BackendTask Deep Dive" "Dillon Kearns" "Understanding the BackendTask abstraction and how it enables powerful server-side data loading."
        , post "Testing Elm Apps" "Aaron VonderHaar" "Write reliable tests for your Elm code using elm-test and elm-program-test."
        , post "Why Referential Transparency Matters" "Richard Feldman" "How pure functions enable powerful testing, refactoring, and reasoning about code."
        ]


post : String -> String -> String -> Encode.Value
post title author excerpt =
    Encode.object
        [ ( "title", Encode.string title )
        , ( "author", Encode.string author )
        , ( "excerpt", Encode.string excerpt )
        ]



-- TEST 1: Blog full user journey


blogFullJourney : PagesProgram.ProgramTest Blog.Model Blog.Msg
blogFullJourney =
    PagesProgram.start
        { data = Blog.data
        , init = Blog.init
        , update = Blog.update
        , view = Blog.view
        }
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/posts"
            samplePosts
        |> PagesProgram.ensureViewHas [ PSelector.text "Blog" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Getting Started with Elm" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "BackendTask Deep Dive" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Testing Elm Apps" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "by Dillon Kearns" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "by Aaron VonderHaar" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Show GitHub Stars" ]
        |> PagesProgram.clickButton "Show GitHub Stars"
        |> PagesProgram.simulateHttpGet
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Encode.object [ ( "stargazers_count", Encode.int 4200 ) ])
        |> PagesProgram.ensureViewHasNot [ PSelector.text "Show GitHub Stars" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "elm-pages has 4200 stars" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Getting Started with Elm" ]



-- TEST 2: Login flow


type LoginMsg
    = UpdateEmail String
    | UpdatePassword String
    | SubmitLogin
    | LoginSuccess String
    | ToggleRemember Bool


loginFlowTest :
    PagesProgram.ProgramTest
        { email : String
        , password : String
        , remember : Bool
        , loggedIn : Bool
        , userName : String
        , error : Maybe String
        }
        LoginMsg
loginFlowTest =
    PagesProgram.start
        { data = BackendTask.succeed ()
        , init =
            \() ->
                ( { email = ""
                  , password = ""
                  , remember = False
                  , loggedIn = False
                  , userName = ""
                  , error = Nothing
                  }
                , []
                )
        , update =
            \msg model ->
                case msg of
                    UpdateEmail email ->
                        ( { model | email = email }, [] )

                    UpdatePassword pw ->
                        ( { model | password = pw }, [] )

                    ToggleRemember checked ->
                        ( { model | remember = checked }, [] )

                    SubmitLogin ->
                        if String.isEmpty model.email then
                            ( { model | error = Just "Email is required" }, [] )

                        else if String.length model.password < 6 then
                            ( { model | error = Just "Password must be at least 6 characters" }, [] )

                        else
                            ( model
                            , [ BackendTask.Http.getJson
                                    "https://api.example.com/auth"
                                    (Decode.field "name" Decode.string)
                                    |> BackendTask.allowFatal
                                    |> BackendTask.map LoginSuccess
                              ]
                            )

                    LoginSuccess name ->
                        ( { model | loggedIn = True, userName = name, error = Nothing }, [] )
        , view =
            \_ model ->
                if model.loggedIn then
                    { title = "Dashboard"
                    , body =
                        [ Html.div [ Attr.style "padding" "40px", Attr.style "font-family" "sans-serif" ]
                            [ Html.h1 [] [ Html.text ("Welcome back, " ++ model.userName ++ "!") ]
                            , Html.p [ Attr.style "color" "#666" ] [ Html.text "You are now logged in." ]
                            , Html.div [ Attr.style "margin-top" "20px", Attr.style "padding" "16px", Attr.style "background" "#f0f9ff", Attr.style "border-radius" "8px" ]
                                [ Html.text "Your dashboard content goes here." ]
                            ]
                        ]
                    }

                else
                    { title = "Login"
                    , body =
                        [ Html.div [ Attr.style "max-width" "400px", Attr.style "margin" "40px auto", Attr.style "padding" "30px", Attr.style "font-family" "sans-serif" ]
                            [ Html.h1 [ Attr.style "margin-bottom" "24px" ] [ Html.text "Log In" ]
                            , case model.error of
                                Just err ->
                                    Html.div [ Attr.style "color" "#dc2626", Attr.style "padding" "12px", Attr.style "background" "#fef2f2", Attr.style "border-radius" "6px", Attr.style "margin-bottom" "16px" ]
                                        [ Html.text err ]

                                Nothing ->
                                    Html.text ""
                            , Html.div [ Attr.style "margin-bottom" "16px" ]
                                [ Html.label [ Attr.for "email", Attr.style "display" "block", Attr.style "margin-bottom" "4px", Attr.style "font-weight" "600" ] [ Html.text "Email" ]
                                , Html.input [ Attr.id "email", Attr.type_ "email", Attr.value model.email, Html.Events.onInput UpdateEmail, Attr.style "width" "100%", Attr.style "padding" "8px", Attr.style "border" "1px solid #ccc", Attr.style "border-radius" "4px" ] []
                                ]
                            , Html.div [ Attr.style "margin-bottom" "16px" ]
                                [ Html.label [ Attr.for "password", Attr.style "display" "block", Attr.style "margin-bottom" "4px", Attr.style "font-weight" "600" ] [ Html.text "Password" ]
                                , Html.input [ Attr.id "password", Attr.type_ "password", Attr.value model.password, Html.Events.onInput UpdatePassword, Attr.style "width" "100%", Attr.style "padding" "8px", Attr.style "border" "1px solid #ccc", Attr.style "border-radius" "4px" ] []
                                ]
                            , Html.div [ Attr.style "margin-bottom" "20px" ]
                                [ Html.input [ Attr.id "remember", Attr.type_ "checkbox", Attr.checked model.remember, Html.Events.onCheck ToggleRemember ] []
                                , Html.label [ Attr.for "remember", Attr.style "margin-left" "8px" ] [ Html.text "Remember me" ]
                                ]
                            , Html.button [ Html.Events.onClick SubmitLogin, Attr.style "width" "100%", Attr.style "padding" "10px", Attr.style "background" "#2563eb", Attr.style "color" "white", Attr.style "border" "none", Attr.style "border-radius" "6px", Attr.style "font-size" "16px", Attr.style "cursor" "pointer" ] [ Html.text "Log In" ]
                            ]
                        ]
                    }
        }
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas [ PSelector.text "Log In" ]
        -- Try submitting empty form -> validation error
        |> PagesProgram.clickButton "Log In"
        |> PagesProgram.ensureViewHas [ PSelector.text "Email is required" ]
        -- Fill in email but short password
        |> PagesProgram.fillIn "email" "Email" "alice@example.com"
        |> PagesProgram.fillIn "password" "Password" "123"
        |> PagesProgram.clickButton "Log In"
        |> PagesProgram.ensureViewHas [ PSelector.text "Password must be at least 6 characters" ]
        -- Fill in valid credentials
        |> PagesProgram.fillIn "password" "Password" "secret123"
        |> PagesProgram.check "remember" True
        |> PagesProgram.clickButton "Log In"
        -- Resolve the auth API call
        |> PagesProgram.resolveBackendTask
            (BackendTaskTest.simulateHttpGet
                "https://api.example.com/auth"
                (Encode.object [ ( "name", Encode.string "Alice" ) ])
            )
        -- Should now see the dashboard
        |> PagesProgram.ensureViewHas [ PSelector.text "Welcome back, Alice!" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "You are now logged in." ]



-- TEST 3: Todo app


type TodoMsg
    = UpdateNewTodo String
    | AddTodo
    | ToggleTodo Int
    | DeleteTodo Int


todoAppTest :
    PagesProgram.ProgramTest
        { newTodo : String
        , todos : List { id : Int, text : String, done : Bool }
        , nextId : Int
        }
        TodoMsg
todoAppTest =
    PagesProgram.start
        { data = BackendTask.succeed ()
        , init =
            \() ->
                ( { newTodo = ""
                  , todos =
                        [ { id = 1, text = "Learn Elm", done = True }
                        , { id = 2, text = "Build elm-pages app", done = False }
                        , { id = 3, text = "Write tests", done = False }
                        ]
                  , nextId = 4
                  }
                , []
                )
        , update =
            \msg model ->
                case msg of
                    UpdateNewTodo text ->
                        ( { model | newTodo = text }, [] )

                    AddTodo ->
                        if String.isEmpty (String.trim model.newTodo) then
                            ( model, [] )

                        else
                            ( { model
                                | todos = model.todos ++ [ { id = model.nextId, text = model.newTodo, done = False } ]
                                , newTodo = ""
                                , nextId = model.nextId + 1
                              }
                            , []
                            )

                    ToggleTodo id ->
                        ( { model
                            | todos =
                                List.map
                                    (\todo ->
                                        if todo.id == id then
                                            { todo | done = not todo.done }

                                        else
                                            todo
                                    )
                                    model.todos
                          }
                        , []
                        )

                    DeleteTodo id ->
                        ( { model | todos = List.filter (\todo -> todo.id /= id) model.todos }, [] )
        , view =
            \_ model ->
                let
                    completedCount : Int
                    completedCount =
                        List.length (List.filter .done model.todos)

                    totalCount : Int
                    totalCount =
                        List.length model.todos
                in
                { title = "Todos (" ++ String.fromInt completedCount ++ "/" ++ String.fromInt totalCount ++ ")"
                , body =
                    [ Html.div [ Attr.style "max-width" "500px", Attr.style "margin" "40px auto", Attr.style "padding" "20px", Attr.style "font-family" "sans-serif" ]
                        [ Html.h1 [] [ Html.text "Todo List" ]
                        , Html.p [ Attr.style "color" "#666" ]
                            [ Html.text (String.fromInt completedCount ++ " of " ++ String.fromInt totalCount ++ " completed") ]
                        , Html.div [ Attr.style "display" "flex", Attr.style "gap" "8px", Attr.style "margin" "16px 0" ]
                            [ Html.input
                                [ Attr.id "new-todo"
                                , Attr.placeholder "What needs to be done?"
                                , Attr.value model.newTodo
                                , Html.Events.onInput UpdateNewTodo
                                , Attr.style "flex" "1"
                                , Attr.style "padding" "8px"
                                , Attr.style "border" "1px solid #ccc"
                                , Attr.style "border-radius" "4px"
                                ]
                                []
                            , Html.button
                                [ Html.Events.onClick AddTodo
                                , Attr.style "padding" "8px 16px"
                                , Attr.style "background" "#10b981"
                                , Attr.style "color" "white"
                                , Attr.style "border" "none"
                                , Attr.style "border-radius" "4px"
                                , Attr.style "cursor" "pointer"
                                ]
                                [ Html.text "Add" ]
                            ]
                        , Html.ul [ Attr.style "list-style" "none", Attr.style "padding" "0" ]
                            (List.map
                                (\todo ->
                                    Html.li
                                        [ Attr.style "display" "flex"
                                        , Attr.style "align-items" "center"
                                        , Attr.style "padding" "8px 0"
                                        , Attr.style "border-bottom" "1px solid #eee"
                                        ]
                                        [ Html.input
                                            [ Attr.type_ "checkbox"
                                            , Attr.checked todo.done
                                            , Attr.id ("todo-" ++ String.fromInt todo.id)
                                            , Html.Events.onCheck (\_ -> ToggleTodo todo.id)
                                            ]
                                            []
                                        , Html.span
                                            [ Attr.style "flex" "1"
                                            , Attr.style "margin-left" "12px"
                                            , Attr.style "text-decoration"
                                                (if todo.done then
                                                    "line-through"

                                                 else
                                                    "none"
                                                )
                                            , Attr.style "color"
                                                (if todo.done then
                                                    "#999"

                                                 else
                                                    "#333"
                                                )
                                            ]
                                            [ Html.text todo.text ]
                                        , Html.button
                                            [ Html.Events.onClick (DeleteTodo todo.id)
                                            , Attr.style "color" "#ef4444"
                                            , Attr.style "background" "none"
                                            , Attr.style "border" "none"
                                            , Attr.style "cursor" "pointer"
                                            ]
                                            [ Html.text "Delete" ]
                                        ]
                                )
                                model.todos
                            )
                        ]
                    ]
                }
        }
        |> PagesProgram.withModelInspector Debug.toString
        -- Initial state: 3 todos, 1 completed
        |> PagesProgram.ensureViewHas [ PSelector.text "Todo List" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "1 of 3 completed" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Learn Elm" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Build elm-pages app" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Write tests" ]
        -- Add a new todo
        |> PagesProgram.fillIn "new-todo" "" "Deploy to production"
        |> PagesProgram.clickButton "Add"
        |> PagesProgram.ensureViewHas [ PSelector.text "Deploy to production" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "1 of 4 completed" ]
        -- Complete "Build elm-pages app"
        |> PagesProgram.check "todo-2" True
        |> PagesProgram.ensureViewHas [ PSelector.text "2 of 4 completed" ]
        -- Complete "Write tests"
        |> PagesProgram.check "todo-3" True
        |> PagesProgram.ensureViewHas [ PSelector.text "3 of 4 completed" ]
        -- Delete completed "Learn Elm" (use within to scope since multiple Delete buttons)
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ Selector.text "Learn Elm" ] ])
            (PagesProgram.clickButton "Delete")
        |> PagesProgram.ensureViewHas [ PSelector.text "2 of 3 completed" ]



-- TEST 4: Blog loads posts (simple)


blogLoadsPostsTest : PagesProgram.ProgramTest Blog.Model Blog.Msg
blogLoadsPostsTest =
    PagesProgram.start
        { data = Blog.data
        , init = Blog.init
        , update = Blog.update
        , view = Blog.view
        }
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/posts"
            samplePosts
        |> PagesProgram.ensureViewHas [ PSelector.text "Getting Started with Elm" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "by Dillon Kearns" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "by Richard Feldman" ]



-- TEST 5: Counter with model inspector


type CounterMsg
    = Increment


counterTest : PagesProgram.ProgramTest { count : Int } CounterMsg
counterTest =
    PagesProgram.start
        { data = BackendTask.succeed ()
        , init = \() -> ( { count = 0 }, [] )
        , update =
            \msg model ->
                case msg of
                    Increment ->
                        ( { model | count = model.count + 1 }, [] )
        , view =
            \_ model ->
                { title = "Counter: " ++ String.fromInt model.count
                , body =
                    [ Html.div [ Attr.style "padding" "40px", Attr.style "font-family" "sans-serif", Attr.style "text-align" "center" ]
                        [ Html.h1 [] [ Html.text "Counter" ]
                        , Html.p [ Attr.style "font-size" "72px", Attr.style "margin" "20px 0", Attr.style "font-weight" "bold", Attr.style "color" "#2563eb" ]
                            [ Html.text (String.fromInt model.count) ]
                        , Html.button
                            [ Html.Events.onClick Increment
                            , Attr.style "padding" "12px 32px"
                            , Attr.style "font-size" "20px"
                            , Attr.style "cursor" "pointer"
                            , Attr.style "background" "#2563eb"
                            , Attr.style "color" "white"
                            , Attr.style "border" "none"
                            , Attr.style "border-radius" "8px"
                            ]
                            [ Html.text "+1" ]
                        ]
                    ]
                }
        }
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.clickButton "+1"



-- TEST 6: Search with filtering


type SearchMsg
    = UpdateSearch String


searchTest : PagesProgram.ProgramTest { search : String, items : List String } SearchMsg
searchTest =
    PagesProgram.start
        { data =
            BackendTask.succeed
                { items =
                    [ "Elm", "elm-pages", "elm-ui", "elm-css"
                    , "elm-test", "elm-review", "elm-format"
                    , "Haskell", "PureScript", "Rust"
                    ]
                }
        , init = \pageData -> ( { search = "", items = pageData.items }, [] )
        , update =
            \msg model ->
                case msg of
                    UpdateSearch q ->
                        ( { model | search = q }, [] )
        , view =
            \_ model ->
                let
                    filtered : List String
                    filtered =
                        if String.isEmpty model.search then
                            model.items

                        else
                            List.filter
                                (\item -> String.contains (String.toLower model.search) (String.toLower item))
                                model.items
                in
                { title = "Search (" ++ String.fromInt (List.length filtered) ++ " results)"
                , body =
                    [ Html.div [ Attr.style "max-width" "400px", Attr.style "margin" "40px auto", Attr.style "padding" "20px", Attr.style "font-family" "sans-serif" ]
                        [ Html.h1 [] [ Html.text "Package Search" ]
                        , Html.input
                            [ Attr.id "search"
                            , Attr.placeholder "Search packages..."
                            , Attr.value model.search
                            , Html.Events.onInput UpdateSearch
                            , Attr.style "width" "100%"
                            , Attr.style "padding" "10px"
                            , Attr.style "border" "1px solid #ccc"
                            , Attr.style "border-radius" "6px"
                            , Attr.style "font-size" "16px"
                            , Attr.style "margin-bottom" "16px"
                            ]
                            []
                        , Html.p [ Attr.style "color" "#666", Attr.style "margin-bottom" "12px" ]
                            [ Html.text (String.fromInt (List.length filtered) ++ " results") ]
                        , Html.ul [ Attr.style "list-style" "none", Attr.style "padding" "0" ]
                            (List.map
                                (\item ->
                                    Html.li [ Attr.style "padding" "8px 12px", Attr.style "border-bottom" "1px solid #eee" ]
                                        [ Html.text item ]
                                )
                                filtered
                            )
                        ]
                    ]
                }
        }
        |> PagesProgram.withModelInspector Debug.toString
        |> PagesProgram.ensureViewHas [ PSelector.text "10 results" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Haskell" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "elm-pages" ]
        -- Search for "elm"
        |> PagesProgram.fillIn "search" "" "elm"
        |> PagesProgram.ensureViewHas [ PSelector.text "7 results" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.text "Haskell" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.text "Rust" ]
        -- Narrow to "elm-"
        |> PagesProgram.fillIn "search" "" "elm-"
        |> PagesProgram.ensureViewHas [ PSelector.text "5 results" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.text "Elm" ]
        -- Search for something specific
        |> PagesProgram.fillIn "search" "" "review"
        |> PagesProgram.ensureViewHas [ PSelector.text "1 results" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "elm-review" ]
