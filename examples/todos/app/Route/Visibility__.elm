module Route.Visibility__ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Handler
import Form.Validation as Validation
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2)
import Icon
import Json.Decode as Decode
import Json.Encode as Encode
import LoadingSpinner
import MySession
import Pages.Form
import Pages.Navigation exposing (FetcherSubmitStatus(..))
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute)
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
            , subscriptions = \_ _ _ _ -> Sub.none
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
    , id : String
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
    { errors : Maybe String
    }


toOptimisticTodo : Todo -> Entry
toOptimisticTodo todo =
    { description = todo.description
    , completed = todo.completed
    , isSaving = False
    , id = todo.id
    }


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init app shared =
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
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
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


performAction : Time.Posix -> Action -> String -> BackendTask FatalError (Response ActionData ErrorPage)
performAction requestTime actionInput sessionId =
    case actionInput of
        Add newItemDescription ->
            if newItemDescription |> String.contains "error" then
                BackendTask.succeed (Response.render { errors = Just "Cannot contain the word error" })

            else
                BackendTask.Custom.run "createTodo"
                    (Encode.object
                        [ ( "sessionId", sessionId |> Encode.string )
                        , ( "requestTime", requestTime |> Time.posixToMillis |> Encode.int )
                        , ( "description", newItemDescription |> Encode.string )
                        ]
                    )
                    (Decode.succeed ())
                    |> BackendTask.allowFatal
                    |> BackendTask.map (\_ -> Response.render { errors = Nothing })

        UpdateEntry ( itemId, newDescription ) ->
            BackendTask.Custom.run "updateTodo"
                (Encode.object
                    [ ( "sessionId", sessionId |> Encode.string )
                    , ( "todoId", itemId |> Encode.string )
                    , ( "description", newDescription |> Encode.string )
                    ]
                )
                (Decode.succeed ())
                |> BackendTask.allowFatal
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        Delete itemId ->
            BackendTask.Custom.run "deleteTodo"
                (Encode.object
                    [ ( "sessionId", sessionId |> Encode.string )
                    , ( "todoId", itemId |> Encode.string )
                    ]
                )
                (Decode.succeed ())
                |> BackendTask.allowFatal
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        DeleteComplete ->
            BackendTask.Custom.run "clearCompletedTodos"
                (Encode.object
                    [ ( "sessionId", sessionId |> Encode.string )
                    ]
                )
                (Decode.succeed ())
                |> BackendTask.allowFatal
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        Check ( newCompleteValue, itemId ) ->
            BackendTask.Custom.run "setTodoCompletion"
                (Encode.object
                    [ ( "sessionId", sessionId |> Encode.string )
                    , ( "todoId", itemId |> Encode.string )
                    , ( "complete", newCompleteValue |> Encode.bool )
                    ]
                )
                (Decode.succeed ())
                |> BackendTask.allowFatal
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        CheckAll toggleTo ->
            BackendTask.Custom.run "checkAllTodos"
                (Encode.object
                    [ ( "sessionId", sessionId |> Encode.string )
                    , ( "toggleTo", toggleTo |> Encode.bool )
                    ]
                )
                (Decode.succeed ())
                |> BackendTask.allowFatal
                |> BackendTask.map (\() -> Response.render { errors = Nothing })


data : RouteParams -> Request.Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.requestTime
        |> MySession.expectSessionDataOrRedirect (Session.get "sessionId")
            (\parsedSession requestTime session ->
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
                                        { entries = todos |> List.map toOptimisticTodo
                                        , visibility = visibility
                                        , requestTime = requestTime
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


type alias Todo =
    { description : String
    , completed : Bool
    , id : String
    }


todoDecoder : Decode.Decoder Todo
todoDecoder =
    Decode.map3 Todo
        (Decode.field "title" Decode.string)
        (Decode.field "complete" Decode.bool)
        (Decode.field "id" Decode.string)


action : RouteParams -> Request.Parser (BackendTask FatalError (Response ActionData ErrorPage))
action routeParams =
    Request.map2 Tuple.pair
        Request.requestTime
        (Request.formData allForms)
        |> MySession.withSession
            (\( requestTime, ( formResponse, formResult ) ) session ->
                let
                    okSession : Session
                    okSession =
                        session
                            |> Result.withDefault Session.empty
                in
                case formResult of
                    Form.Valid actionInput ->
                        (okSession |> Session.get "sessionId" |> Maybe.withDefault "")
                            |> performAction requestTime actionInput
                            |> BackendTask.map (Tuple.pair okSession)

                    Form.Invalid _ _ ->
                        BackendTask.succeed ( okSession, Response.render { errors = Nothing } )
            )


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


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared model =
    let
        pendingFetchers : List Action
        pendingFetchers =
            app.concurrentSubmissions
                |> Dict.values
                |> List.filterMap
                    (\{ status, payload } ->
                        case status of
                            FetcherComplete thing ->
                                case thing of
                                    Just thisActionData ->
                                        case thisActionData.errors of
                                            Just error ->
                                                -- Items with errors will show up in `failedAddItemActions` (queued up so the user can edit failed items),
                                                -- so we leave them out here.
                                                Nothing

                                            Nothing ->
                                                -- This was a successfully created item. Don't add it because it's now in `app.data`
                                                Nothing

                                    Nothing ->
                                        Nothing

                            _ ->
                                allForms
                                    |> Form.Handler.run payload.fields
                                    |> Form.toResult
                                    |> Result.toMaybe
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
                                    , id = ""
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
                        if (isClearing && item.completed) || (deletingItems |> Set.member item.id) then
                            Nothing

                        else
                            case togglingAllTo of
                                Just justTogglingAllTo ->
                                    Just { item | completed = justTogglingAllTo }

                                Nothing ->
                                    case togglingItems |> Dict.get item.id of
                                        Just toggleTo ->
                                            Just { item | completed = toggleTo, isSaving = True }

                                        Nothing ->
                                            Just item
                    )
            )
                ++ creatingItems

        optimisticVisibility : Visibility
        optimisticVisibility =
            case app.navigation of
                Just (Pages.Navigation.Loading path _) ->
                    case path of
                        [ "active" ] ->
                            Active

                        [ "completed" ] ->
                            Completed

                        _ ->
                            All

                _ ->
                    app.data.visibility

        failedAddItemActions : List ( String, String )
        failedAddItemActions =
            app.concurrentSubmissions
                |> Dict.toList
                |> List.filterMap
                    (\( key, { status, payload } ) ->
                        case
                            ( allForms
                                |> Form.Handler.run payload.fields
                            , status
                            )
                        of
                            ( Form.Valid (Add newItem), Pages.Navigation.FetcherComplete (Just parsedActionData) ) ->
                                parsedActionData.errors
                                    |> Maybe.map (Tuple.pair key)

                            _ ->
                                Nothing
                    )
    in
    { title = "Elm • TodoMVC"
    , body =
        [ div
            [ class "todomvc-wrapper"
            ]
            [ section
                [ class "todoapp" ]
                [ addItemForm
                    |> Pages.Form.renderHtml
                        [ class "create-form"
                        , hidden (not (List.isEmpty failedAddItemActions))
                        ]
                        (Form.options
                            ("new-item-"
                                ++ (model.nextId |> Time.posixToMillis |> String.fromInt)
                            )
                            |> Form.withInput Nothing
                            |> Form.withOnSubmit (\_ -> NewItemSubmitted)
                            |> Pages.Form.withConcurrent
                        )
                        app
                , div []
                    (failedAddItemActions
                        |> List.indexedMap
                            (\index ( key, createFetcherErrors ) ->
                                addItemForm
                                    |> Pages.Form.renderHtml
                                        [ class "create-form", hidden (index /= 0) ]
                                        (Form.options key
                                            |> Form.withOnSubmit (\_ -> NewItemSubmitted)
                                            |> Form.withInput (Just createFetcherErrors)
                                            |> Pages.Form.withConcurrent
                                        )
                                        app
                            )
                    )
                , viewEntries app optimisticVisibility optimisticEntities
                , viewControls app optimisticVisibility optimisticEntities
                ]
            , infoFooter
            ]
        ]
    }



-- FORMS


allForms : Form.Handler.Handler String Action
allForms =
    editItemForm
        |> Form.Handler.init UpdateEntry
        |> Form.Handler.with Add addItemForm
        |> Form.Handler.with Check checkItemForm
        |> Form.Handler.with Delete deleteItemForm
        |> Form.Handler.with (\_ -> DeleteComplete) clearCompletedForm
        |> Form.Handler.with CheckAll toggleAllForm


addItemForm : Form.HtmlForm String String (Maybe String) msg
addItemForm =
    Form.form
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
                        , formState.input |> Maybe.map (\error -> Html.div [ class "error", id "new-todo-error" ] [ text error ]) |> Maybe.withDefault (text "")
                        ]
                    ]
            }
        )
        |> Form.field "description" (Field.text |> Field.required "Must be present")
        |> Form.hiddenKind ( "kind", "new-item" ) "Expected kind"


editItemForm : Form.HtmlForm String ( String, String ) Entry msg
editItemForm =
    Form.form
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
                        , id ("todo-" ++ formState.input.id)
                        ]
                        description
                    ]
            }
        )
        |> Form.hiddenField "itemId"
            (Field.text
                |> Field.withInitialValue .id
                |> Field.required "Must be present"
            )
        |> Form.field "description"
            (Field.text
                |> Field.withInitialValue .description
                |> Field.required "Must be present"
            )
        |> Form.hiddenKind ( "kind", "edit-item" ) "Expected kind"


deleteItemForm : Form.HtmlForm String String Entry msg
deleteItemForm =
    Form.form
        (\todoId ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap todoId
            , view =
                \_ ->
                    [ button [ class "destroy" ] [] ]
            }
        )
        |> Form.hiddenField "todoId"
            (Field.text
                |> Field.required "Must be present"
                |> Field.withInitialValue .id
            )
        |> Form.hiddenKind ( "kind", "delete" ) "Expected kind"


toggleAllForm : Form.HtmlForm String Bool { allCompleted : Bool } msg
toggleAllForm =
    Form.form
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
                            , ( "checked", formState.input.allCompleted )
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
                |> Field.withInitialValue (not << .allCompleted)
            )
        |> Form.hiddenKind ( "kind", "toggle-all" ) "Expected kind"


checkItemForm : Form.HtmlForm String ( Bool, String ) Entry msg
checkItemForm =
    Form.form
        (\todoId complete ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap complete
                    |> Validation.andMap todoId
            , view =
                \formState ->
                    [ Html.button [ class "toggle" ]
                        [ if formState.input.completed then
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
                |> Field.withInitialValue .id
            )
        |> Form.hiddenField "complete"
            (Field.checkbox
                |> Field.withInitialValue (.completed >> not)
            )
        |> Form.hiddenKind ( "kind", "complete" ) "Expected kind"


clearCompletedForm : Form.HtmlForm String () { entriesCompleted : Int } msg
clearCompletedForm =
    Form.form
        { combine = Validation.succeed ()
        , view =
            \formState ->
                [ button
                    [ class "clear-completed"
                    , hidden (formState.input.entriesCompleted == 0)
                    ]
                    [ text ("Clear completed (" ++ String.fromInt formState.input.entriesCompleted ++ ")")
                    ]
                ]
        }
        |> Form.hiddenKind ( "kind", "clear-completed" ) "Expected kind"



-- VIEW ALL ENTRIES


viewEntries : App Data ActionData RouteParams -> Visibility -> List Entry -> Html (PagesMsg Msg)
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
            |> Pages.Form.renderHtml []
                (Form.options "toggle-all"
                    |> Form.withInput { allCompleted = allCompleted }
                    |> Pages.Form.withConcurrent
                )
                app
        , Keyed.ul [ class "todo-list" ] <|
            List.map (viewKeyedEntry app) (List.filter isVisible entries)
        ]



-- VIEW INDIVIDUAL ENTRIES


viewKeyedEntry : App Data ActionData RouteParams -> Entry -> ( String, Html (PagesMsg Msg) )
viewKeyedEntry app todo =
    ( todo.id, lazy2 viewEntry app todo )


viewEntry : App Data ActionData RouteParams -> Entry -> Html (PagesMsg Msg)
viewEntry app todo =
    li
        [ classList
            [ ( "completed", todo.completed )
            ]
        ]
        [ div
            [ class "view" ]
            [ checkItemForm
                |> Pages.Form.renderHtml []
                    (("toggle-" ++ todo.id)
                        |> Form.options
                        |> Form.withInput todo
                        |> Pages.Form.withConcurrent
                    )
                    app
            , editItemForm
                |> Pages.Form.renderHtml []
                    (Form.options ("edit-" ++ todo.id)
                        |> Form.withInput todo
                        |> Pages.Form.withConcurrent
                    )
                    app
            , if todo.isSaving then
                LoadingSpinner.view

              else
                deleteItemForm
                    |> Pages.Form.renderHtml []
                        (Form.options ("delete-" ++ todo.id)
                            |> Form.withInput todo
                            |> Pages.Form.withConcurrent
                        )
                        app
            ]
        ]



-- VIEW CONTROLS AND FOOTER


viewControls : App Data ActionData RouteParams -> Visibility -> List Entry -> Html (PagesMsg Msg)
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


viewControlsCount : Int -> Html (PagesMsg Msg)
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


viewControlsFilters : Visibility -> Html (PagesMsg Msg)
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


visibilitySwap : Maybe String -> Visibility -> Visibility -> Html (PagesMsg Msg)
visibilitySwap visibilityParam visibility actualVisibility =
    li
        []
        [ Route.Visibility__ { visibility = visibilityParam }
            |> Route.link
                [ classList [ ( "selected", visibility == actualVisibility ) ] ]
                [ visibility |> visibilityToString |> text ]
        ]


viewControlsClear : App Data ActionData RouteParams -> Int -> Html (PagesMsg Msg)
viewControlsClear app entriesCompleted =
    clearCompletedForm
        |> Pages.Form.renderHtml []
            (Form.options "clear-completed"
                |> Form.withInput { entriesCompleted = entriesCompleted }
                |> Pages.Form.withConcurrent
            )
            app


infoFooter : Html msg
infoFooter =
    footer [ class "info" ]
        [ p [] [ text "Click to edit a todo" ]
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
