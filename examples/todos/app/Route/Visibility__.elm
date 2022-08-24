module Route.Visibility__ exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Session
import Data.Todo
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Validation as Validation
import Form.Value
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2)
import Icon
import LoadingSpinner
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Transition
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session exposing (Session)
import Set exposing (Set)
import Shared
import Task
import Time
import View exposing (View)


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = \_ -> []
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = \_ _ _ _ _ -> Sub.none
            , init = init
            }



-- MODEL
-- The full application state of our todo app.


type alias Model =
    { nextId : Time.Posix
    }


type alias Entry =
    { description : String
    , completed : Bool
    , isSaving : Bool
    , id : Uuid
    }


type Msg
    = NewItemSubmitted
    | GenerateNextNewItemId Time.Posix


type alias RouteParams =
    { visibility : Maybe String }


type alias Data =
    { entries : List Entry
    , visibility : Visibility
    , requestTime : Time.Posix
    }


type alias ActionData =
    {}


toOptimisticTodo : Data.Todo.Todo -> Entry
toOptimisticTodo todo =
    { description = todo.description
    , completed = todo.completed
    , isSaving = False
    , id = todo.id
    }


init : Maybe PageUrl -> Shared.Model -> StaticPayload Data ActionData RouteParams -> ( Model, Effect Msg )
init maybePageUrl sharedModel app =
    ( { nextId = app.data.requestTime }
    , Effect.none
    )



-- UPDATE


{-| elm-pages apps only use Msg's and Model state for client-side interaction, but most of the behavior in
Todo MVC is handled by our `action` which is an Elm function that runs server-side and can handle form submissions
and other server requests.

Most of our state moves out of the `Model` and into more declarative state in the URL (`RouteParams`) and
form submissions (`Action`). Since elm-pages handles client-side form state, we don't need equivalents for some of these
Msg's like `UpdateField`, `EditingEntry`. We don't need the `ChangeVisibility` because we use the declarative URL
state from `RouteParams` instead.

Some onClick handlers also go away because forms parse into one of these `Action` variants when it is received on the server.

-}
type Action
    = UpdateEntry ( String, String )
    | Add String
    | Delete String
    | DeleteComplete
    | Check ( Bool, String )
    | CheckAll Bool



-- How we update our Model on a given Msg?


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NewItemSubmitted ->
            ( model
            , Time.now
                |> Task.perform GenerateNextNewItemId
                |> Effect.fromCmd
            )

        GenerateNextNewItemId currentTime ->
            -- this will clear out the input from the previous input because we will use
            -- the new form-id to render the new item form
            ( { model | nextId = currentTime }, Effect.none )


performAction : Time.Posix -> Action -> Uuid -> DataSource (Response ActionData ErrorPage)
performAction requestTime actionInput userId =
    case actionInput of
        Add newItemDescription ->
            Data.Todo.create requestTime userId newItemDescription
                |> Request.Hasura.mutationDataSource
                |> DataSource.map (\_ -> Response.render {})

        UpdateEntry ( itemId, newDescription ) ->
            Data.Todo.update
                { userId = userId
                , todoId = Uuid itemId
                , newDescription = newDescription
                }
                |> Request.Hasura.mutationDataSource
                |> DataSource.map (\() -> Response.render {})

        Delete itemId ->
            Data.Todo.delete
                { userId = userId
                , itemId = Uuid itemId
                }
                |> Request.Hasura.mutationDataSource
                |> DataSource.map (\() -> Response.render {})

        DeleteComplete ->
            Data.Todo.clearCompletedTodos userId
                |> Request.Hasura.mutationDataSource
                |> DataSource.map (\() -> Response.render {})

        Check ( newCompleteValue, itemId ) ->
            Data.Todo.setCompleteTo
                { userId = userId
                , itemId = Uuid itemId
                , newCompleteValue = newCompleteValue
                }
                |> Request.Hasura.mutationDataSource
                |> DataSource.map (\() -> Response.render {})

        CheckAll toggleTo ->
            Data.Todo.toggleAllTo userId toggleTo
                |> Request.Hasura.mutationDataSource
                |> DataSource.map (\() -> Response.render {})


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.requestTime
        |> MySession.expectSessionDataOrRedirect (Session.get "sessionId")
            (\parsedSession requestTime session ->
                case visibilityFromRouteParams routeParams of
                    Just visibility ->
                        Data.Todo.findAllBySession parsedSession
                            |> Request.Hasura.dataSource
                            |> DataSource.map
                                (\todos ->
                                    ( session
                                    , Response.render
                                        { entries =
                                            todos
                                                -- TODO add error handling for Nothing case
                                                |> Maybe.withDefault []
                                                |> List.map toOptimisticTodo
                                        , visibility = visibility
                                        , requestTime = requestTime
                                        }
                                    )
                                )

                    Nothing ->
                        DataSource.succeed
                            ( session
                            , Route.Visibility__ { visibility = Nothing }
                                |> Route.redirectTo
                            )
            )


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    MySession.withSession
        (Request.map2 Tuple.pair
            Request.requestTime
            (Request.formData allForms)
        )
        (\( requestTime, formResult ) session ->
            case formResult of
                Ok actionInput ->
                    actionInput
                        |> performAction requestTime
                        |> withUserSession session

                Err _ ->
                    let
                        okSession : Session
                        okSession =
                            session
                                |> Result.withDefault Nothing
                                |> Maybe.withDefault Session.empty
                    in
                    DataSource.succeed ( okSession, Response.render {} )
        )


withUserSession :
    Result x (Maybe Session)
    -> (Uuid -> DataSource (Response ActionData ErrorPage))
    -> DataSource ( Session, Response ActionData ErrorPage )
withUserSession cookieSession continue =
    let
        okSession : Session
        okSession =
            cookieSession
                |> Result.withDefault Nothing
                |> Maybe.withDefault Session.empty
    in
    okSession
        |> Session.get "sessionId"
        |> Maybe.map Data.Session.get
        |> Maybe.map Request.Hasura.dataSource
        |> Maybe.map
            (DataSource.andThen
                (\maybeUserSession ->
                    let
                        maybeUserId : Maybe Uuid
                        maybeUserId =
                            maybeUserSession
                                |> Maybe.map .id
                    in
                    case maybeUserId of
                        Nothing ->
                            DataSource.succeed ( okSession, Response.render {} )

                        Just userId ->
                            continue userId
                                |> DataSource.map (Tuple.pair okSession)
                )
            )
        |> Maybe.withDefault (DataSource.succeed ( okSession, Response.render {} ))


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


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    let
        pendingFetchers : List Action
        pendingFetchers =
            app.fetchers
                |> List.filterMap
                    (\{ status, payload } ->
                        allForms
                            |> Form.runOneOfServerSide payload.fields
                            |> Tuple.first
                    )

        creatingItems : List Entry
        creatingItems =
            pendingFetchers
                |> List.filterMap
                    (\fetcher ->
                        case fetcher of
                            Add description ->
                                Just
                                    { description = description
                                    , completed = False
                                    , id = Uuid ""
                                    , isSaving = True
                                    }

                            _ ->
                                Nothing
                    )

        isClearing : Bool
        isClearing =
            pendingFetchers
                |> List.any
                    (\fetcher -> fetcher == DeleteComplete)

        deletingItems : Set String
        deletingItems =
            pendingFetchers
                |> List.filterMap
                    (\fetcher ->
                        case fetcher of
                            Delete id ->
                                Just id

                            _ ->
                                Nothing
                    )
                |> Set.fromList

        togglingItems : Dict String Bool
        togglingItems =
            pendingFetchers
                |> List.filterMap
                    (\fetcher ->
                        case fetcher of
                            Check ( bool, id ) ->
                                Just ( id, bool )

                            _ ->
                                Nothing
                    )
                |> Dict.fromList

        togglingAllTo : Maybe Bool
        togglingAllTo =
            pendingFetchers
                |> List.filterMap
                    (\fetcher ->
                        case fetcher of
                            CheckAll toggleTo ->
                                Just toggleTo

                            _ ->
                                Nothing
                    )
                |> List.head

        optimisticEntities : List Entry
        optimisticEntities =
            (app.data.entries
                |> List.filterMap
                    (\item ->
                        if (isClearing && item.completed) || (deletingItems |> Set.member (uuidToString item.id)) then
                            Nothing

                        else
                            case togglingAllTo of
                                Just justTogglingAllTo ->
                                    Just { item | completed = justTogglingAllTo }

                                Nothing ->
                                    case togglingItems |> Dict.get (uuidToString item.id) of
                                        Just toggleTo ->
                                            Just { item | completed = toggleTo, isSaving = True }

                                        Nothing ->
                                            Just item
                    )
            )
                ++ creatingItems

        optimisticVisibility : Visibility
        optimisticVisibility =
            case app.transition of
                Just (Pages.Transition.Loading path _) ->
                    case path |> Path.toSegments of
                        [ "active" ] ->
                            Active

                        [ "completed" ] ->
                            Completed

                        _ ->
                            All

                _ ->
                    app.data.visibility
    in
    { title = "Elm • TodoMVC"
    , body =
        [ div
            [ class "todomvc-wrapper"
            ]
            [ section
                [ class "todoapp" ]
                [ newItemForm
                    |> Form.toDynamicFetcher
                        ("new-item-"
                            ++ (model.nextId |> Time.posixToMillis |> String.fromInt)
                        )
                    |> Form.withOnSubmit (\_ -> NewItemSubmitted)
                    |> Form.renderHtml
                        [ class "create-form" ]
                        Nothing
                        app
                        ()
                , viewEntries app optimisticVisibility optimisticEntities
                , viewControls app optimisticVisibility optimisticEntities
                ]
            , infoFooter
            ]
        ]
    }


newItemForm : Form.HtmlForm String String input Msg
newItemForm =
    Form.init
        (\description ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap description
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
                        , Html.button [ style "display" "none" ] [ Html.text "Create" ]
                        ]
                    ]
            }
        )
        |> Form.field "description" (Field.text |> Field.required "Must be present")
        |> Form.hiddenKind ( "kind", "new-item" ) "Expected kind"


allForms : Form.ServerForms String Action
allForms =
    editItemForm
        |> Form.initCombined UpdateEntry
        |> Form.combine Add newItemForm
        |> Form.combine Check completeItemForm
        |> Form.combine Delete deleteItemForm
        |> Form.combine (\_ -> DeleteComplete) clearCompletedForm
        |> Form.combine CheckAll toggleAllForm



-- VIEW
-- VIEW ALL ENTRIES


viewEntries : StaticPayload Data ActionData RouteParams -> Visibility -> List Entry -> Html (Pages.Msg.Msg Msg)
viewEntries app visibility entries =
    let
        isVisible todo =
            case visibility of
                Completed ->
                    todo.completed

                Active ->
                    not todo.completed

                All ->
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
        [ toggleAllForm
            |> Form.toDynamicFetcher "toggle-all"
            |> Form.renderHtml [] Nothing app { allCompleted = allCompleted }
        , Keyed.ul [ class "todo-list" ] <|
            List.map (viewKeyedEntry app) (List.filter isVisible entries)
        ]


toggleAllForm : Form.HtmlForm String Bool { allCompleted : Bool } Msg
toggleAllForm =
    Form.init
        (\toggleTo ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap toggleTo
            , view =
                \formState ->
                    [ button
                        [ classList
                            [ ( "toggle-all", True )
                            , ( "toggle", True )
                            , ( "checked", formState.data.allCompleted )
                            ]
                        ]
                        [ text "❯" ]
                    , label
                        [ for "toggle-all", style "display" "none" ]
                        [ text "Mark all as complete" ]
                    ]
            }
        )
        |> Form.hiddenField "toggleTo"
            (Field.checkbox
                |> Field.withInitialValue
                    (\{ allCompleted } ->
                        Form.Value.bool (not allCompleted)
                    )
            )
        |> Form.hiddenKind ( "kind", "toggle-all" ) "Expected kind"



-- VIEW INDIVIDUAL ENTRIES


viewKeyedEntry : StaticPayload Data ActionData RouteParams -> Entry -> ( String, Html (Pages.Msg.Msg Msg) )
viewKeyedEntry app todo =
    ( uuidToString todo.id, lazy2 viewEntry app todo )


viewEntry : StaticPayload Data ActionData RouteParams -> Entry -> Html (Pages.Msg.Msg Msg)
viewEntry app todo =
    li
        [ classList
            [ ( "completed", todo.completed )
            ]
        ]
        [ div
            [ class "view" ]
            [ completeItemForm
                |> Form.toDynamicFetcher ("toggle-" ++ uuidToString todo.id)
                |> Form.renderHtml [] Nothing app todo
            , editItemForm
                |> Form.toDynamicFetcher ("edit-" ++ uuidToString todo.id)
                |> Form.renderHtml [] Nothing app todo
            , if todo.isSaving then
                LoadingSpinner.view

              else
                deleteItemForm
                    |> Form.toDynamicFetcher ("delete-" ++ uuidToString todo.id)
                    |> Form.renderHtml [] Nothing app todo
            ]
        ]


completeItemForm : Form.HtmlForm String ( Bool, String ) Entry Msg
completeItemForm =
    Form.init
        (\todoId complete ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap complete
                    |> Validation.andMap todoId
            , view =
                \formState ->
                    [ Html.button [ class "toggle" ]
                        [ if formState.data.completed then
                            Icon.complete

                          else
                            Icon.incomplete
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


editItemForm : Form.HtmlForm String ( String, String ) Entry Msg
editItemForm =
    Form.init
        (\itemId description ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap itemId
                    |> Validation.andMap description
            , view =
                \formState ->
                    [ FieldView.input
                        [ class "edit-input"
                        , name "title"
                        , id ("todo-" ++ uuidToString formState.data.id)
                        ]
                        description
                    , Html.button [ style "display" "none" ] []
                    ]
            }
        )
        |> Form.hiddenField "itemId"
            (Field.text
                |> Field.withInitialValue (.id >> uuidToString >> Form.Value.string)
                |> Field.required "Must be present"
            )
        |> Form.field "description"
            (Field.text
                |> Field.withInitialValue (.description >> Form.Value.string)
                |> Field.required "Must be present"
            )
        |> Form.hiddenKind ( "kind", "edit-item" ) "Expected kind"


deleteItemForm : Form.HtmlForm String String Entry Msg
deleteItemForm =
    Form.init
        (\todoId ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap todoId
            , view =
                \formState ->
                    [ button [ class "destroy" ] [] ]
            }
        )
        |> Form.hiddenField "todoId"
            (Field.text
                |> Field.required "Must be present"
                |> Field.withInitialValue (.id >> uuidToString >> Form.Value.string)
            )
        |> Form.hiddenKind ( "kind", "delete" ) "Expected kind"


uuidToString : Uuid -> String
uuidToString (Uuid uuid) =
    uuid



-- VIEW CONTROLS AND FOOTER


viewControls : StaticPayload Data ActionData RouteParams -> Visibility -> List Entry -> Html (Pages.Msg.Msg Msg)
viewControls app visibility entries =
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
        , lazy2 viewControlsClear app entriesCompleted
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


type Visibility
    = All
    | Active
    | Completed


viewControlsFilters : Visibility -> Html (Pages.Msg.Msg Msg)
viewControlsFilters visibility =
    ul
        [ class "filters" ]
        [ visibilitySwap Nothing All visibility
        , text " "
        , visibilitySwap (Just "active") Active visibility
        , text " "
        , visibilitySwap (Just "completed") Completed visibility
        ]


visibilityToString : Visibility -> String
visibilityToString visibility =
    case visibility of
        All ->
            "All"

        Active ->
            "Active"

        Completed ->
            "Completed"


visibilitySwap : Maybe String -> Visibility -> Visibility -> Html (Pages.Msg.Msg Msg)
visibilitySwap visibilityParam visibility actualVisibility =
    li
        []
        [ Route.Visibility__ { visibility = visibilityParam }
            |> Route.link
                [ classList [ ( "selected", visibility == actualVisibility ) ] ]
                [ visibility |> visibilityToString |> text ]
        ]


clearCompletedForm : Form.HtmlForm String () { entriesCompleted : Int } Msg
clearCompletedForm =
    Form.init
        { combine = Validation.succeed ()
        , view =
            \formState ->
                [ button
                    [ class "clear-completed"
                    , hidden (formState.data.entriesCompleted == 0)
                    ]
                    [ text ("Clear completed (" ++ String.fromInt formState.data.entriesCompleted ++ ")")
                    ]
                ]
        }
        |> Form.hiddenKind ( "kind", "clear-completed" ) "Expected kind"


viewControlsClear : StaticPayload Data ActionData RouteParams -> Int -> Html (Pages.Msg.Msg Msg)
viewControlsClear app entriesCompleted =
    clearCompletedForm
        |> Form.toDynamicFetcher "clear-completed"
        |> Form.renderHtml [] Nothing app { entriesCompleted = entriesCompleted }


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
