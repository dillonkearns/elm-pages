module PageTests exposing
    ( loginFlowTest
    , todoAppTest
    , searchFilterTest
    , counterTest
    )

{-| Rich page tests for the end-to-end example.
View in browser: elm-pages dev, then open localhost:1234/_tests
-}

import BackendTask
import BackendTask.Http
import Html
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram exposing (ProgramTest)
import Test.Html.Selector as PSelector



-- LOGIN FLOW


type LoginMsg
    = UpdateEmail String
    | UpdatePassword String
    | SubmitLogin
    | LoginSuccess String
    | ToggleRemember Bool


loginFlowTest : ProgramTest { email : String, password : String, remember : Bool, loggedIn : Bool, userName : String, error : Maybe String } LoginMsg
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
        |> PagesProgram.clickButton "Log In"
        |> PagesProgram.ensureViewHas [ PSelector.text "Email is required" ]
        |> PagesProgram.fillIn "email" "email" "alice@example.com"
        |> PagesProgram.fillIn "password" "password" "123"
        |> PagesProgram.clickButton "Log In"
        |> PagesProgram.ensureViewHas [ PSelector.text "Password must be at least 6 characters" ]
        |> PagesProgram.fillIn "password" "password" "secret123"
        |> PagesProgram.check "Remember me" True
        |> PagesProgram.clickButton "Log In"
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/auth"
            (Encode.object [ ( "name", Encode.string "Alice" ) ])
        |> PagesProgram.ensureViewHas [ PSelector.text "Welcome back, Alice!" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "You are now logged in." ]



-- TODO APP


type TodoMsg
    = UpdateNewTodo String
    | AddTodo
    | ToggleTodo Int
    | DeleteTodo Int


todoAppTest : ProgramTest { newTodo : String, todos : List { id : Int, text : String, done : Bool }, nextId : Int } TodoMsg
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
                    completedCount =
                        List.length (List.filter .done model.todos)

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
                                        , Html.label [ Attr.for ("todo-" ++ String.fromInt todo.id) ] [ Html.text todo.text ]
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
        |> PagesProgram.ensureViewHas [ PSelector.text "Todo List" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "1 of 3 completed" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Learn Elm" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Build elm-pages app" ]
        |> PagesProgram.fillIn "new-todo" "new-todo" "Deploy to production"
        |> PagesProgram.clickButton "Add"
        |> PagesProgram.ensureViewHas [ PSelector.text "Deploy to production" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "1 of 4 completed" ]
        |> PagesProgram.check "Build elm-pages app" True
        |> PagesProgram.ensureViewHas [ PSelector.text "2 of 4 completed" ]
        |> PagesProgram.check "Write tests" True
        |> PagesProgram.ensureViewHas [ PSelector.text "3 of 4 completed" ]
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ Selector.text "Learn Elm" ] ])
            (PagesProgram.clickButton "Delete")
        |> PagesProgram.ensureViewHas [ PSelector.text "2 of 3 completed" ]



-- SEARCH WITH FILTERING


type SearchMsg
    = UpdateSearch String


searchFilterTest : ProgramTest { search : String, items : List String } SearchMsg
searchFilterTest =
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
        |> PagesProgram.fillIn "search" "search" "elm"
        |> PagesProgram.ensureViewHas [ PSelector.text "7 results" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.text "Haskell" ]
        |> PagesProgram.fillIn "search" "search" "elm-"
        |> PagesProgram.ensureViewHas [ PSelector.text "6 results" ]
        |> PagesProgram.fillIn "search" "search" "review"
        |> PagesProgram.ensureViewHas [ PSelector.text "1 results" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "elm-review" ]



-- COUNTER


type CounterMsg
    = Increment


counterTest : ProgramTest { count : Int } CounterMsg
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
