module Route.Todos exposing (ActionData, Data, Model, Msg, route)

import Api.InputObject
import Api.Mutation
import Api.Object exposing (Todos)
import Api.Object.Todos
import Api.Query
import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import MySession
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    { todos : List Todo
    }


type alias ActionData =
    {}


todosByUserId : Int -> SelectionSet (List Todo) RootQuery
todosByUserId userId =
    Api.Query.todos
        (\optionals ->
            { optionals
                | where_ =
                    Present
                        (Api.InputObject.buildTodos_bool_exp
                            (\whereOptionals ->
                                { whereOptionals
                                    | user_id =
                                        Api.InputObject.buildInt_comparison_exp
                                            (\intOptionals ->
                                                { intOptionals | eq_ = Present <| userId }
                                            )
                                            |> Present
                                }
                            )
                        )
            }
        )
        (SelectionSet.map3 Todo
            Api.Object.Todos.title
            Api.Object.Todos.is_completed
            Api.Object.Todos.id
        )


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.requestTime
        |> MySession.expectSessionOrRedirect
            (\requestTime session ->
                let
                    maybeUserId : Maybe Int
                    maybeUserId =
                        session
                            |> Session.get "userId"
                            |> Maybe.andThen String.toInt
                in
                case maybeUserId of
                    Just userId ->
                        todosByUserId userId
                            |> Request.Hasura.backendTask (requestTime |> Time.posixToMillis |> String.fromInt)
                            |> BackendTask.map
                                (\todos ->
                                    ( session
                                    , Response.render { todos = todos }
                                    )
                                )

                    Nothing ->
                        ( session, Route.redirectTo Route.Login )
                            |> BackendTask.succeed
            )


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    let
        userId =
            1
    in
    Request.expectFormPost
        (\{ field } ->
            Request.oneOf
                [ field "newTodo"
                    |> Request.map
                        (\title ->
                            createTodo userId title
                                |> Request.Hasura.mutationBackendTask ""
                                |> BackendTask.map
                                    (\_ -> Response.render {})
                        )
                , field "deleteId"
                    |> Request.map
                        (\deleteId ->
                            -- TODO use RBAC here in Hasura?
                            deleteTodo userId (deleteId |> String.toInt |> Maybe.withDefault 0)
                                |> Request.Hasura.mutationBackendTask ""
                                |> BackendTask.map
                                    (\_ -> Response.render {})
                        )
                ]
        )


createTodo : Int -> String -> SelectionSet (Maybe ()) Graphql.Operation.RootMutation
createTodo userId title =
    Api.Mutation.insert_todos_one identity
        { object =
            Api.InputObject.buildTodos_insert_input
                (\optionals ->
                    { optionals
                        | title = Present title
                        , user_id = Present userId
                    }
                )
        }
        SelectionSet.empty


deleteTodo : Int -> Int -> SelectionSet (Maybe ()) Graphql.Operation.RootMutation
deleteTodo userId todoId =
    Api.Mutation.delete_todos_by_pk { id = todoId }
        SelectionSet.empty


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "Todo List"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model static =
    { title = "Todo List"
    , body =
        [ Html.div
            [ Attr.class "todomvc-wrapper"
            ]
            [ Html.section
                [ Attr.class "todoapp"
                ]
                [ Html.header
                    [ Attr.class "header"
                    ]
                    [ Html.h1 []
                        [ Html.text "todos" ]
                    , Html.form
                        [ Attr.method "POST"
                        , Pages.Msg.fetcherOnSubmit
                        ]
                        [ Html.input
                            [ Attr.class "new-todo"
                            , Attr.placeholder "What needs to be done?"
                            , Attr.autofocus True
                            , Attr.name "newTodo"
                            ]
                            []
                        , Html.button [] [ Html.text "Create" ]
                        ]
                    ]
                , Html.section
                    [ Attr.class "main"
                    , Attr.style "visibility" "visible"
                    ]
                    [ Html.input
                        [ Attr.class "toggle-all"
                        , Attr.id "toggle-all"
                        , Attr.type_ "checkbox"
                        , Attr.name "toggle"
                        ]
                        []
                    , Html.label
                        [ Attr.for "toggle-all"
                        ]
                        [ Html.text "Mark all as complete" ]
                    , Html.ul
                        [ Attr.class "todo-list"
                        ]
                        (static.data.todos
                            |> List.map todoItemView
                        )
                    ]
                , Html.footer
                    [ Attr.class "footer"
                    ]
                    [ Html.span
                        [ Attr.class "todo-count"
                        ]
                        [ Html.strong []
                            [ Html.text "3" ]
                        , Html.text " items left"
                        ]
                    , Html.ul
                        [ Attr.class "filters"
                        ]
                        [ Html.li []
                            [ Html.a
                                [ Attr.class "selected"
                                , Attr.href "#/"
                                ]
                                [ Html.text "All" ]
                            ]
                        , Html.li []
                            [ Html.a
                                [ Attr.class ""
                                , Attr.href "#/active"
                                ]
                                [ Html.text "Active" ]
                            ]
                        , Html.li []
                            [ Html.a
                                [ Attr.class ""
                                , Attr.href "#/completed"
                                ]
                                [ Html.text "Completed" ]
                            ]
                        ]
                    , Html.button
                        [ Attr.class "clear-completed"
                        , Attr.hidden True
                        ]
                        [ Html.text "Clear completed (0)" ]
                    ]
                ]
            , Html.footer
                [ Attr.class "info"
                ]
                [ Html.p []
                    [ Html.text "Double-click to edit a todo" ]
                , Html.p []
                    [ Html.text "Written by "
                    , Html.a
                        [ Attr.href "https://github.com/dillonkearns"
                        ]
                        [ Html.text "Dillon Kearns" ]
                    ]
                , Html.p []
                    [ Html.text "Part of "
                    , Html.a
                        [ Attr.href "http://todomvc.com"
                        ]
                        [ Html.text "TodoMVC" ]
                    ]
                ]
            ]
        ]
    }


type alias Todo =
    { title : String
    , complete : Bool
    , id : Int
    }


todoItemView : Todo -> Html (PagesMsg Msg)
todoItemView todo =
    Html.li []
        [ Html.div
            [ Attr.class "view"
            , Pages.Msg.fetcherOnSubmit
            ]
            [ Html.form
                [ Attr.method "POST"
                ]
                [ Html.input
                    [ Attr.class "toggle"
                    , Attr.type_ "checkbox"
                    , Attr.checked todo.complete

                    --, Html.Events.onCheck  (\_ -> Pages.Msg.Submit )
                    ]
                    []
                , Html.label []
                    [ Html.text todo.title ]
                ]
            , Html.form [ Attr.method "POST", Pages.Msg.fetcherOnSubmit ]
                [ Html.button
                    [ Attr.class "destroy"
                    ]
                    []
                , Html.input [ Attr.type_ "hidden", Attr.name "deleteId", Attr.value (String.fromInt todo.id) ] []
                ]
            ]
        , Html.input
            [ Attr.class "edit"
            , Attr.name "title"

            --, Attr.id "todo-0"
            ]
            []
        ]
