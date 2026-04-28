module Route.Visibility__ exposing (ActionData, Data, Model, Msg, route)

{-| TEA-focused TodoMVC.

Data is loaded from the server via BackendTask, but all interactions
(add, toggle, delete, filter) happen client-side through the Model.

This contrasts with the original todos example where every mutation is
a server round-trip via form submission.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Html exposing (..)
import Html.Attributes exposing (autofocus, checked, class, classList, for, hidden, href, id, placeholder, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed as Keyed
import Json.Decode as Decode
import Json.Encode as Encode
import MySession
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = \_ -> []
        , data = data
        , action = \_ _ -> BackendTask.succeed (Response.render {})
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = \_ _ _ _ -> Sub.none
            , init = init
            }



-- MODEL


type alias Entry =
    { description : String
    , completed : Bool
    , id : String
    }


type alias Model =
    { entries : List Entry
    , newInput : String
    , nextId : Int
    , visibility : Visibility
    }


type Visibility
    = All
    | Active
    | Completed


type Msg
    = UpdateInput String
    | AddTodo
    | ToggleTodo String
    | DeleteTodo String
    | ToggleAll
    | ClearCompleted
    | SetVisibility Visibility
    | NoOp


type alias RouteParams =
    { visibility : Maybe String }


type alias Data =
    { entries : List Entry
    , visibility : Visibility
    }


type alias ActionData =
    {}


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init app _ =
    ( { entries = app.data.entries
      , newInput = ""
      , nextId =
            app.data.entries
                |> List.filterMap (.id >> String.toInt)
                |> List.maximum
                |> Maybe.withDefault 0
                |> (+) 1
      , visibility = app.data.visibility
      }
    , Effect.none
    )



-- UPDATE


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        UpdateInput str ->
            ( { model | newInput = str }, Effect.none )

        AddTodo ->
            if String.isEmpty (String.trim model.newInput) then
                ( model, Effect.none )

            else
                ( { model
                    | entries =
                        model.entries
                            ++ [ { description = String.trim model.newInput
                                 , completed = False
                                 , id = String.fromInt model.nextId
                                 }
                               ]
                    , newInput = ""
                    , nextId = model.nextId + 1
                  }
                , Effect.none
                )

        ToggleTodo todoId ->
            ( { model
                | entries =
                    List.map
                        (\entry ->
                            if entry.id == todoId then
                                { entry | completed = not entry.completed }

                            else
                                entry
                        )
                        model.entries
              }
            , Effect.none
            )

        DeleteTodo todoId ->
            ( { model
                | entries = List.filter (\entry -> entry.id /= todoId) model.entries
              }
            , Effect.none
            )

        ToggleAll ->
            let
                allCompleted =
                    List.all .completed model.entries
            in
            ( { model
                | entries =
                    List.map (\entry -> { entry | completed = not allCompleted }) model.entries
              }
            , Effect.none
            )

        ClearCompleted ->
            ( { model
                | entries = List.filter (\entry -> not entry.completed) model.entries
              }
            , Effect.none
            )

        SetVisibility v ->
            ( { model | visibility = v }, Effect.none )

        NoOp ->
            ( model, Effect.none )



-- DATA


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    request
        |> MySession.expectSessionDataOrRedirect (Session.get "sessionId")
            (\parsedSession session ->
                case visibilityFromRouteParams routeParams of
                    Just visibility ->
                        BackendTask.Custom.run "getTodosBySession"
                            (Encode.string parsedSession)
                            (Decode.list todoDecoder)
                            |> BackendTask.allowFatal
                            |> BackendTask.map
                                (\todos ->
                                    ( session
                                    , Response.render
                                        { entries = todos
                                        , visibility = visibility
                                        }
                                    )
                                )

                    Nothing ->
                        BackendTask.succeed
                            ( session
                            , Route.Visibility__ { visibility = Nothing }
                                |> Route.redirectTo
                            )
            )


todoDecoder : Decode.Decoder Entry
todoDecoder =
    Decode.map3 Entry
        (Decode.field "title" Decode.string)
        (Decode.field "complete" Decode.bool)
        (Decode.field "id" Decode.string)


visibilityFromRouteParams : RouteParams -> Maybe Visibility
visibilityFromRouteParams { visibility } =
    case visibility of
        Nothing ->
            Just All

        Just "completed" ->
            Just Completed

        Just "active" ->
            Just Active

        _ ->
            Nothing



-- VIEW


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app _ model =
    let
        visibleEntries =
            case model.visibility of
                All ->
                    model.entries

                Active ->
                    List.filter (\e -> not e.completed) model.entries

                Completed ->
                    List.filter .completed model.entries

        entriesCompleted =
            List.length (List.filter .completed model.entries)

        entriesLeft =
            List.length model.entries - entriesCompleted

        allCompleted =
            List.all .completed model.entries
    in
    { title = "Elm • TodoMVC"
    , body =
        [ div [ class "todomvc-wrapper" ]
            [ section [ class "todoapp" ]
                [ viewInput model.newInput
                , viewEntries allCompleted visibleEntries
                , viewControls model.visibility entriesLeft entriesCompleted
                ]
            , infoFooter
            ]
        ]
    }


viewInput : String -> Html (PagesMsg Msg)
viewInput currentInput =
    header [ class "header" ]
        [ h1 [] [ text "todos" ]
        , input
            [ class "new-todo"
            , placeholder "What needs to be done?"
            , autofocus True
            , value currentInput
            , onInput (PagesMsg.fromMsg << UpdateInput)
            , Html.Events.on "keydown"
                (Html.Events.keyCode
                    |> Decode.andThen
                        (\keyCode ->
                            if keyCode == 13 then
                                Decode.succeed (PagesMsg.fromMsg AddTodo)

                            else
                                Decode.fail "not enter"
                        )
                )
            ]
            []
        ]


viewEntries : Bool -> List Entry -> Html (PagesMsg Msg)
viewEntries allCompleted entries =
    let
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
            , id "toggle-all"
            , type_ "checkbox"
            , checked allCompleted
            , onClick (PagesMsg.fromMsg ToggleAll)
            ]
            []
        , label [ for "toggle-all" ] [ text "Mark all as complete" ]
        , Keyed.ul [ class "todo-list" ]
            (List.map viewKeyedEntry entries)
        ]


viewKeyedEntry : Entry -> ( String, Html (PagesMsg Msg) )
viewKeyedEntry entry =
    ( entry.id, viewEntry entry )


viewEntry : Entry -> Html (PagesMsg Msg)
viewEntry entry =
    li
        [ classList [ ( "completed", entry.completed ) ] ]
        [ div [ class "view" ]
            [ input
                [ class "toggle"
                , type_ "checkbox"
                , checked entry.completed
                , onClick (PagesMsg.fromMsg (ToggleTodo entry.id))
                ]
                []
            , label [] [ text entry.description ]
            , button
                [ class "destroy"
                , onClick (PagesMsg.fromMsg (DeleteTodo entry.id))
                ]
                []
            ]
        ]


viewControls : Visibility -> Int -> Int -> Html (PagesMsg Msg)
viewControls visibility entriesLeft entriesCompleted =
    footer
        [ class "footer"
        , hidden (entriesLeft + entriesCompleted == 0)
        ]
        [ viewControlsCount entriesLeft
        , viewControlsFilters visibility
        , button
            [ class "clear-completed"
            , hidden (entriesCompleted == 0)
            , onClick (PagesMsg.fromMsg ClearCompleted)
            ]
            [ text ("Clear completed (" ++ String.fromInt entriesCompleted ++ ")") ]
        ]


viewControlsCount : Int -> Html msg
viewControlsCount entriesLeft =
    let
        item_ =
            if entriesLeft == 1 then
                " item"

            else
                " items"
    in
    span [ class "todo-count" ]
        [ strong [] [ text (String.fromInt entriesLeft) ]
        , text (item_ ++ " left")
        ]


viewControlsFilters : Visibility -> Html (PagesMsg Msg)
viewControlsFilters visibility =
    ul [ class "filters" ]
        [ filterLink All visibility
        , text " "
        , filterLink Active visibility
        , text " "
        , filterLink Completed visibility
        ]


filterLink : Visibility -> Visibility -> Html (PagesMsg Msg)
filterLink target current =
    li []
        [ a
            [ classList [ ( "selected", target == current ) ]
            , href "#"
            , onClick (PagesMsg.fromMsg (SetVisibility target))
            ]
            [ text (visibilityToString target) ]
        ]


visibilityToString : Visibility -> String
visibilityToString v =
    case v of
        All ->
            "All"

        Active ->
            "Active"

        Completed ->
            "Completed"


infoFooter : Html msg
infoFooter =
    footer [ class "info" ]
        [ p [] [ text "Double-click to edit a todo" ]
        , p []
            [ text "Written by "
            , a [ href "https://github.com/dillonkearns" ] [ text "Dillon Kearns" ]
            ]
        , p []
            [ text "Part of "
            , a [ href "http://todomvc.com" ] [ text "TodoMVC" ]
            ]
        ]
