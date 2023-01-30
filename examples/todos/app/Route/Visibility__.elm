module Route.Visibility__ exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Data.Session
import Data.Todo
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
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
import Json.Decode as Decode
import Json.Encode as Encode
import LoadingSpinner
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Transition exposing (FetcherSubmitStatus(..))
import Path
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StaticPayload)
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
    { errors : Maybe String
    }


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


performAction : Time.Posix -> Action -> Uuid -> BackendTask FatalError (Response ActionData ErrorPage)
performAction requestTime actionInput userId =
    case actionInput of
        Add newItemDescription ->
            if newItemDescription |> String.contains "error" then
                BackendTask.succeed (Response.render { errors = Just "Cannot contain the word error" })

            else
                Data.Todo.create requestTime userId newItemDescription
                    |> Request.Hasura.mutationBackendTask
                    |> BackendTask.map (\_ -> Response.render { errors = Nothing })

        UpdateEntry ( itemId, newDescription ) ->
            Data.Todo.update
                { userId = userId
                , todoId = Uuid itemId
                , newDescription = newDescription
                }
                |> Request.Hasura.mutationBackendTask
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        Delete itemId ->
            Data.Todo.delete
                { userId = userId
                , itemId = Uuid itemId
                }
                |> Request.Hasura.mutationBackendTask
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        DeleteComplete ->
            Data.Todo.clearCompletedTodos userId
                |> Request.Hasura.mutationBackendTask
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        Check ( newCompleteValue, itemId ) ->
            Data.Todo.setCompleteTo
                { userId = userId
                , itemId = Uuid itemId
                , newCompleteValue = newCompleteValue
                }
                |> Request.Hasura.mutationBackendTask
                |> BackendTask.map (\() -> Response.render { errors = Nothing })

        CheckAll toggleTo ->
            Data.Todo.toggleAllTo userId toggleTo
                |> Request.Hasura.mutationBackendTask
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
    , id : Uuid
    }


todoDecoder : Decode.Decoder Todo
todoDecoder =
    Decode.map3 Todo
        (Decode.field "title" Decode.string)
        (Decode.field "complete" Decode.bool)
        (Decode.field "id" (Decode.string |> Decode.map Uuid))


action : RouteParams -> Request.Parser (BackendTask FatalError (Response ActionData ErrorPage))
action routeParams =
    Request.map2 Tuple.pair
        Request.requestTime
        (Request.formData allForms)
        |> MySession.withSession
            (\( requestTime, ( formResponse, formResult ) ) session ->
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
                                    |> Result.withDefault Session.empty
                        in
                        BackendTask.succeed ( okSession, Response.render { errors = Nothing } )
            )


withUserSession :
    Result x Session
    -> (Uuid -> BackendTask FatalError (Response ActionData ErrorPage))
    -> BackendTask FatalError ( Session, Response ActionData ErrorPage )
withUserSession cookieSession continue =
    let
        okSession : Session
        okSession =
            cookieSession
                |> Result.withDefault Session.empty
    in
    okSession
        |> Session.get "sessionId"
        |> Maybe.map Data.Session.get
        |> Maybe.map Request.Hasura.backendTask
        |> Maybe.map
            (BackendTask.andThen
                (\maybeUserSession ->
                    let
                        maybeUserId : Maybe Uuid
                        maybeUserId =
                            maybeUserSession
                                |> Maybe.map .id
                    in
                    case maybeUserId of
                        Nothing ->
                            BackendTask.succeed ( okSession, Response.render { errors = Nothing } )

                        Just userId ->
                            continue userId
                                |> BackendTask.map (Tuple.pair okSession)
                )
            )
        |> Maybe.withDefault (BackendTask.succeed ( okSession, Response.render { errors = Nothing } ))


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

        failedAddItemActions : List ( String, String )
        failedAddItemActions =
            app.fetchers
                |> Dict.toList
                |> List.filterMap
                    (\( key, { status, payload } ) ->
                        case
                            ( allForms
                                |> Form.runOneOfServerSide payload.fields
                                |> Tuple.first
                            , status
                            )
                        of
                            ( Just (Add newItem), Pages.Transition.FetcherComplete (Just parsedActionData) ) ->
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
                    |> Form.toDynamicFetcher
                        ("new-item-"
                            ++ (model.nextId |> Time.posixToMillis |> String.fromInt)
                        )
                    |> Form.withOnSubmit (\_ -> NewItemSubmitted)
                    |> Form.renderHtml
                        [ class "create-form"
                        , hidden (not (List.isEmpty failedAddItemActions))
                        ]
                        (\_ -> Nothing)
                        app
                        Nothing
                , div []
                    (failedAddItemActions
                        |> List.indexedMap
                            (\index ( key, createFetcherErrors ) ->
                                addItemForm
                                    |> Form.toDynamicFetcher key
                                    |> Form.withOnSubmit (\_ -> NewItemSubmitted)
                                    |> Form.renderHtml [ class "create-form", hidden (index /= 0) ]
                                        (\_ -> Nothing)
                                        app
                                        (Just createFetcherErrors)
                            )
                    )
                , viewEntries app optimisticVisibility optimisticEntities
                , viewControls app optimisticVisibility optimisticEntities
                ]
            , infoFooter

            --, pre [ style "white-space" "break-spaces" ]
            --    [ text
            --        (app.fetchers
            --            |> Dict.toList
            --            |> List.map Debug.toString
            --            |> String.join "\n"
            --        )
            --    ]
            ]
        ]
    }



-- FORMS


allForms : Form.ServerForms String Action
allForms =
    editItemForm
        |> Form.initCombined UpdateEntry
        |> Form.combine Add addItemForm
        |> Form.combine Check checkItemForm
        |> Form.combine Delete deleteItemForm
        |> Form.combine (\_ -> DeleteComplete) clearCompletedForm
        |> Form.combine CheckAll toggleAllForm


addItemForm : Form.HtmlForm String String (Maybe String) Msg
addItemForm =
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
                        , formState.data |> Maybe.map (\error -> Html.div [ class "error", id "new-todo-error" ] [ text error ]) |> Maybe.withDefault (text "")
                        ]
                    ]
            }
        )
        |> Form.field "description" (Field.text |> Field.required "Must be present")
        |> Form.hiddenKind ( "kind", "new-item" ) "Expected kind"


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
                \_ ->
                    [ button [ class "destroy" ] [] ]
            }
        )
        |> Form.hiddenField "todoId"
            (Field.text
                |> Field.required "Must be present"
                |> Field.withInitialValue (.id >> uuidToString >> Form.Value.string)
            )
        |> Form.hiddenKind ( "kind", "delete" ) "Expected kind"


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


checkItemForm : Form.HtmlForm String ( Bool, String ) Entry Msg
checkItemForm =
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
            |> Form.renderHtml [] (\_ -> Nothing) app { allCompleted = allCompleted }
        , Keyed.ul [ class "todo-list" ] <|
            List.map (viewKeyedEntry app) (List.filter isVisible entries)
        ]



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
            [ checkItemForm
                |> Form.toDynamicFetcher ("toggle-" ++ uuidToString todo.id)
                |> Form.renderHtml [] (\_ -> Nothing) app todo
            , editItemForm
                |> Form.toDynamicFetcher ("edit-" ++ uuidToString todo.id)
                |> Form.renderHtml [] (\_ -> Nothing) app todo
            , if todo.isSaving then
                LoadingSpinner.view

              else
                deleteItemForm
                    |> Form.toDynamicFetcher ("delete-" ++ uuidToString todo.id)
                    |> Form.renderHtml [] (\_ -> Nothing) app todo
            ]
        ]


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


viewControlsClear : StaticPayload Data ActionData RouteParams -> Int -> Html (Pages.Msg.Msg Msg)
viewControlsClear app entriesCompleted =
    clearCompletedForm
        |> Form.toDynamicFetcher "clear-completed"
        |> Form.renderHtml [] (\_ -> Nothing) app { entriesCompleted = entriesCompleted }


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
