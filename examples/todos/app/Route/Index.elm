module Route.Index exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Session
import Data.Todo exposing (Todo)
import DataSource exposing (DataSource)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Validation as Validation
import Form.Value
import Head
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2, lazy3)
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Request.Hasura
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Seo.Common
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session exposing (Session)
import Shared
import View exposing (View)


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


type alias Model =
    { visibility : String
    }


type Msg
    = NoOp
    | ChangeVisibility String


type alias RouteParams =
    {}


type alias Data =
    { entries : List Todo
    }


type alias ActionData =
    {}


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( { visibility = "All"
      }
    , Effect.none
    )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        ChangeVisibility visibility ->
            ( { model | visibility = visibility }
            , Effect.none
            )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.Common.tags


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> MySession.expectSessionDataOrRedirect (Session.get "sessionId")
            (\parsedSession () session ->
                Data.Todo.findAllBySession parsedSession
                    |> Request.Hasura.dataSource
                    |> DataSource.map
                        (\todos ->
                            ( session
                            , Response.render
                                { entries = todos |> Maybe.withDefault [] -- TODO add error handling for Nothing case
                                }
                            )
                        )
            )


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    MySession.withSession
        (Request.formData [ newItemForm, completeItemForm, deleteItemForm ])
        (\formResult session ->
            let
                okSessionThing : Session
                okSessionThing =
                    session
                        |> Result.withDefault Nothing
                        |> Maybe.withDefault Session.empty
            in
            case formResult |> Debug.log "formResult" of
                Ok (DeleteItem itemId) ->
                    okSessionThing
                        |> Session.get "sessionId"
                        |> Maybe.map Data.Session.get
                        |> Maybe.map Request.Hasura.dataSource
                        |> Maybe.map
                            (DataSource.andThen
                                (\maybeUserSession ->
                                    let
                                        bar : Maybe Uuid
                                        bar =
                                            maybeUserSession
                                                |> Maybe.map .id
                                    in
                                    case bar of
                                        Nothing ->
                                            DataSource.succeed
                                                ( okSessionThing
                                                , Response.render {}
                                                )

                                        Just userId ->
                                            Data.Todo.delete
                                                ({ userId = userId
                                                 , itemId = Uuid itemId
                                                 }
                                                    |> Debug.log "@delete"
                                                )
                                                |> Request.Hasura.mutationDataSource
                                                |> DataSource.map
                                                    (\() ->
                                                        ( okSessionThing
                                                        , Response.render {}
                                                        )
                                                    )
                                )
                            )
                        |> Maybe.withDefault
                            (DataSource.succeed
                                ( okSessionThing
                                , Response.render {}
                                )
                            )

                Ok (ToggleItem ( newCompleteValue, itemId )) ->
                    okSessionThing
                        |> Session.get "sessionId"
                        |> Maybe.map Data.Session.get
                        |> Maybe.map Request.Hasura.dataSource
                        |> Maybe.map
                            (DataSource.andThen
                                (\maybeUserSession ->
                                    let
                                        bar : Maybe Uuid
                                        bar =
                                            maybeUserSession
                                                |> Maybe.map .id
                                    in
                                    case bar of
                                        Nothing ->
                                            DataSource.succeed
                                                ( okSessionThing
                                                , Response.render {}
                                                )

                                        Just userId ->
                                            Data.Todo.setCompleteTo
                                                { userId = userId
                                                , itemId = Uuid itemId
                                                , newCompleteValue = newCompleteValue
                                                }
                                                |> Request.Hasura.mutationDataSource
                                                |> DataSource.map
                                                    (\() ->
                                                        ( okSessionThing
                                                        , Response.render {}
                                                        )
                                                    )
                                )
                            )
                        |> Maybe.withDefault
                            (DataSource.succeed
                                ( okSessionThing
                                , Response.render {}
                                )
                            )

                Ok (CreateItem newItemDescription) ->
                    okSessionThing
                        |> Session.get "sessionId"
                        |> Maybe.map Data.Session.get
                        |> Maybe.map Request.Hasura.dataSource
                        |> Maybe.map
                            (DataSource.andThen
                                (\maybeUserSession ->
                                    let
                                        bar : Maybe Uuid
                                        bar =
                                            maybeUserSession
                                                |> Maybe.map .id
                                    in
                                    case bar of
                                        Nothing ->
                                            DataSource.succeed
                                                ( okSessionThing
                                                , Response.render {}
                                                )

                                        Just userId ->
                                            Data.Todo.create userId newItemDescription
                                                |> Request.Hasura.mutationDataSource
                                                |> DataSource.map
                                                    (\newItemId ->
                                                        ( okSessionThing
                                                        , Response.render {}
                                                        )
                                                    )
                                )
                            )
                        |> Maybe.withDefault
                            (DataSource.succeed
                                ( okSessionThing
                                , Response.render {}
                                )
                            )

                Err _ ->
                    DataSource.succeed
                        ( okSessionThing
                        , Response.render {}
                        )
        )


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Elm • TodoMVC"
    , body =
        [ div
            [ class "todomvc-wrapper"
            , style "visibility" "hidden"
            ]
            [ section
                [ class "todoapp" ]
                [ newItemForm
                    |> Form.toDynamicFetcher "new-item"
                    |> Form.renderHtml [] Nothing app ()
                , lazy3 viewEntries app model.visibility app.data.entries
                , lazy2 viewControls model.visibility app.data.entries
                ]
            , infoFooter
            ]
        ]
    }



-- VIEW


newItemForm : Form.HtmlForm String Action input Msg
newItemForm =
    Form.init
        (\description ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap description
                    |> Validation.map CreateItem
            , view =
                \formState ->
                    [ header
                        [ class "header" ]
                        [ h1 [] [ text "todos" ]
                        , FieldView.input
                            [ class "new-todo"
                            , placeholder "What needs to be done?"
                            , autofocus True
                            ]
                            description
                        , Html.button [] [ Html.text "Create" ]
                        ]
                    ]
            }
        )
        |> Form.field "description" (Field.text |> Field.required "Must be present")
        |> Form.hiddenKind ( "kind", "new-item" ) "Expected kind"


type Action
    = CreateItem String
    | DeleteItem String
    | ToggleItem ( Bool, String )


completeItemForm : Form.HtmlForm String Action Todo Msg
completeItemForm =
    Form.init
        (\todoId complete ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap complete
                    |> Validation.andMap todoId
                    |> Validation.map ToggleItem
            , view =
                \formState ->
                    [ Html.button []
                        [ Html.text
                            (if formState.data.completed then
                                "( )"

                             else
                                "√"
                            )
                        ]
                    ]
            }
        )
        |> Form.hiddenField "todoId"
            (Field.text
                |> Field.required "Must be present"
                |> Field.withInitialValue (.id >> uuidToString >> Form.Value.string)
            )
        |> Form.hiddenField "complete"
            (Field.checkbox
                |> Field.withInitialValue (.completed >> not >> Form.Value.bool)
            )
        |> Form.hiddenKind ( "kind", "complete" ) "Expected kind"


deleteItemForm : Form.HtmlForm String Action Todo Msg
deleteItemForm =
    Form.init
        (\todoId ->
            { combine =
                Validation.succeed DeleteItem
                    |> Validation.andMap todoId
            , view =
                \formState ->
                    [ button [ class "destroy" ] []
                    ]
            }
        )
        |> Form.hiddenField "todoId"
            (Field.text
                |> Field.required "Must be present"
                |> Field.withInitialValue (.id >> uuidToString >> Form.Value.string)
            )
        |> Form.hiddenKind ( "kind", "delete" ) "Expected kind"



-- VIEW ALL ENTRIES


viewEntries : StaticPayload Data ActionData RouteParams -> String -> List Todo -> Html (Pages.Msg.Msg Msg)
viewEntries app visibility entries =
    let
        isVisible todo =
            case visibility of
                "Completed" ->
                    todo.completed

                "Active" ->
                    not todo.completed

                _ ->
                    True

        allCompleted =
            List.all .completed entries

        cssVisibility =
            if List.isEmpty entries then
                "hidden"

            else
                "visible"
    in
    section
        [ class "main"
        , style "visibility" cssVisibility
        ]
        [ input
            [ class "toggle-all"
            , type_ "checkbox"
            , name "toggle"
            , checked allCompleted

            --, onClick (CheckAll (not allCompleted))
            ]
            []
        , label
            [ for "toggle-all" ]
            [ text "Mark all as complete" ]
        , Keyed.ul [ class "todo-list" ] <|
            List.map (viewKeyedEntry app) (List.filter isVisible entries)
        ]



-- VIEW INDIVIDUAL ENTRIES


viewKeyedEntry : StaticPayload Data ActionData RouteParams -> Todo -> ( String, Html (Pages.Msg.Msg Msg) )
viewKeyedEntry app todo =
    ( uuidToString todo.id, lazy2 viewEntry app todo )


viewEntry : StaticPayload Data ActionData RouteParams -> { description : String, completed : Bool, id : Uuid } -> Html (Pages.Msg.Msg Msg)
viewEntry app todo =
    li
        [ classList
            [ ( "completed", todo.completed )

            --, ( "editing", todo.editing )
            ]
        ]
        [ div
            [ class "view" ]
            [ completeItemForm
                |> Form.toDynamicFetcher ("toggle-" ++ uuidToString todo.id)
                |> Form.renderHtml []
                    Nothing
                    app
                    todo
            , label
                [--onDoubleClick (EditingEntry todo.id True)
                ]
                [ text todo.description ]
            , deleteItemForm
                |> Form.toDynamicFetcher ("delete-" ++ uuidToString todo.id)
                |> Form.renderHtml []
                    Nothing
                    app
                    todo
            ]
        , input
            [ class "edit"
            , value todo.description
            , name "title"
            , id ("todo-" ++ uuidToString todo.id)

            --, onInput (UpdateEntry todo.id)
            --, onBlur (EditingEntry todo.id False)
            --, onEnter (EditingEntry todo.id False)
            ]
            []
        ]


uuidToString : Uuid -> String
uuidToString (Uuid uuid) =
    uuid



-- VIEW CONTROLS AND FOOTER


viewControls : String -> List Todo -> Html (Pages.Msg.Msg Msg)
viewControls visibility entries =
    let
        entriesCompleted =
            List.length (List.filter .completed entries)

        entriesLeft =
            List.length entries - entriesCompleted
    in
    footer
        [ class "footer"
        , hidden (List.isEmpty entries)
        ]
        [ lazy viewControlsCount entriesLeft
        , lazy viewControlsFilters visibility
        , lazy viewControlsClear entriesCompleted
        ]


viewControlsCount : Int -> Html (Pages.Msg.Msg Msg)
viewControlsCount entriesLeft =
    let
        item_ =
            if entriesLeft == 1 then
                " item"

            else
                " items"
    in
    span
        [ class "todo-count" ]
        [ strong [] [ text (String.fromInt entriesLeft) ]
        , text (item_ ++ " left")
        ]


viewControlsFilters : String -> Html (Pages.Msg.Msg Msg)
viewControlsFilters visibility =
    ul
        [ class "filters" ]
        [ visibilitySwap "#/" "All" visibility
        , text " "
        , visibilitySwap "#/active" "Active" visibility
        , text " "
        , visibilitySwap "#/completed" "Completed" visibility
        ]


visibilitySwap : String -> String -> String -> Html (Pages.Msg.Msg Msg)
visibilitySwap uri visibility actualVisibility =
    li
        [--onClick (ChangeVisibility visibility)
        ]
        [ a [ href uri, classList [ ( "selected", visibility == actualVisibility ) ] ]
            [ text visibility ]
        ]


viewControlsClear : Int -> Html (Pages.Msg.Msg Msg)
viewControlsClear entriesCompleted =
    button
        [ class "clear-completed"
        , hidden (entriesCompleted == 0)

        --, onClick DeleteComplete
        ]
        [ text ("Clear completed (" ++ String.fromInt entriesCompleted ++ ")")
        ]


infoFooter : Html msg
infoFooter =
    footer [ class "info" ]
        [ p [] [ text "Double-click to edit a todo" ]
        , p []
            [ text "Written by "
            , a [ href "https://github.com/dillonkearns" ] [ text "Dillon Kearns" ]
            ]
        , p []
            [ text "Forked from Evan Czaplicki's vanilla Elm implementation "
            , a [ href "https://github.com/evancz/elm-todomvc/blob/f236e7e56941c7705aba6e42cb020ff515fe3290/src/Main.elm" ] [ text "github.com/evancz/elm-todomvc" ]
            ]
        , p []
            [ text "Part of "
            , a [ href "http://todomvc.com" ] [ text "TodoMVC" ]
            ]
        ]
