module Route.Visibility__ exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Session
import Data.Todo exposing (Todo)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Validation as Validation
import Form.Value
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2, lazy3)
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Transition
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session exposing (Session)
import Set exposing (Set)
import Shared
import Svg
import Svg.Attributes as SvgAttr
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



-- MODEL
-- The full application state of our todo app.


type alias Model =
    {}


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}
    , Effect.none
    )


type Msg
    = NoOp
    | ClearNewItemInput


type alias RouteParams =
    { visibility : Maybe String }


type alias Data =
    { entries : List Todo
    , visibility : Visibility
    }


type alias ActionData =
    {}



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

        ClearNewItemInput ->
            ( model
            , Effect.SetField
                { formId = "new-item"
                , name = "description"
                , value = ""
                }
            )


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    MySession.withSession
        (Request.formData [ newItemForm, completeItemForm, deleteItemForm, editItemForm, clearCompletedForm, toggleAllForm ])
        (\formResult session ->
            let
                okSessionThing : Session
                okSessionThing =
                    session
                        |> Result.withDefault Nothing
                        |> Maybe.withDefault Session.empty
            in
            case formResult of
                Ok (Add newItemDescription) ->
                    withUserSession session
                        (\userId ->
                            Data.Todo.create userId newItemDescription
                                |> Request.Hasura.mutationDataSource
                                |> DataSource.map (\_ -> Response.render {})
                        )

                Ok (CheckAll toggleTo) ->
                    withUserSession session
                        (\userId ->
                            Data.Todo.toggleAllTo userId toggleTo
                                |> Request.Hasura.mutationDataSource
                                |> DataSource.map (\() -> Response.render {})
                        )

                Ok DeleteComplete ->
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
                                            Data.Todo.clearCompletedTodos userId
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

                Ok (UpdateEntry ( itemId, newDescription )) ->
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
                                            Data.Todo.update
                                                { userId = userId
                                                , todoId = Uuid itemId
                                                , newDescription = newDescription
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

                Ok (Delete itemId) ->
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
                                                { userId = userId
                                                , itemId = Uuid itemId
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

                Ok (Check ( newCompleteValue, itemId )) ->
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

                Err _ ->
                    DataSource.succeed
                        ( okSessionThing
                        , Response.render {}
                        )
        )


withUserSession :
    Result x (Maybe Session)
    -> (Uuid -> DataSource (Response ActionData ErrorPage))
    -> DataSource ( Session, Response ActionData ErrorPage )
withUserSession cookieSession continue =
    let
        okSessionThing : Session
        okSessionThing =
            cookieSession
                |> Result.withDefault Nothing
                |> Maybe.withDefault Session.empty
    in
    okSessionThing
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
                            DataSource.succeed
                                ( okSessionThing
                                , Response.render {}
                                )

                        Just userId ->
                            continue userId
                                |> DataSource.map (Tuple.pair okSessionThing)
                )
            )
        |> Maybe.withDefault
            (DataSource.succeed
                ( okSessionThing
                , Response.render {}
                )
            )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Ctrl-R Smoothies"
        , image =
            { url = Pages.Url.external "https://images.unsplash.com/photo-1499750310107-5fef28a66643?ixlib=rb-1.2.1&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=600&q=80"
            , alt = "Desk with a Todo List"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Manage your list"
        , locale = Nothing
        , title = "Ctrl-R Smoothies"
        }
        |> Seo.website


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


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> MySession.expectSessionDataOrRedirect (Session.get "sessionId")
            (\parsedSession () session ->
                case visibilityFromRouteParams routeParams of
                    Just visibility ->
                        Data.Todo.findAllBySession parsedSession
                            |> Request.Hasura.dataSource
                            |> DataSource.map
                                (\todos ->
                                    ( session
                                    , Response.render
                                        { entries = todos |> Maybe.withDefault [] -- TODO add error handling for Nothing case
                                        , visibility = visibility
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
                        [ editItemForm, newItemForm, completeItemForm, deleteItemForm, clearCompletedForm, toggleAllForm ]
                            |> Form.runOneOfServerSide payload.fields
                            |> Tuple.first
                    )

        creatingItems : List Todo
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

        optimisticEntities : List Todo
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
                                            Just { item | completed = toggleTo }

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
                    |> Form.toDynamicFetcher "new-item"
                    |> Form.withOnSubmit (\_ -> ClearNewItemInput)
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



-- VIEW


newItemForm : Form.HtmlForm String Action input Msg
newItemForm =
    Form.init
        (\description ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap description
                    |> Validation.map Add
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


completeItemForm : Form.HtmlForm String Action Todo Msg
completeItemForm =
    Form.init
        (\todoId complete ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap complete
                    |> Validation.andMap todoId
                    |> Validation.map Check
            , view =
                \formState ->
                    [ Html.button [ class "toggle" ]
                        [ if formState.data.completed then
                            completeIcon

                          else
                            incompleteIcon
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


clearCompletedForm : Form.HtmlForm String Action input Msg
clearCompletedForm =
    Form.init
        { combine =
            Validation.succeed DeleteComplete
        , view =
            \formState ->
                [ button
                    [ class "clear-completed"

                    --, hidden (entriesCompleted == 0)
                    ]
                    [ text "Clear completed"

                    -- TODO need to enable merging forms with different input types (and action types) to make this possible (input types are all Todo now,
                    -- need it to be Int)
                    -- text ("Clear completed (" ++ String.fromInt entriesCompleted ++ ")")
                    ]
                ]
        }
        |> Form.hiddenKind ( "kind", "clear-completed" ) "Expected kind"


deleteItemForm : Form.HtmlForm String Action Todo Msg
deleteItemForm =
    Form.init
        (\todoId ->
            { combine =
                Validation.succeed Delete
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


viewEntries : StaticPayload Data ActionData RouteParams -> Visibility -> List Todo -> Html (Pages.Msg.Msg Msg)
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
            |> Form.renderHtml []
                Nothing
                app
                ()
        , Keyed.ul [ class "todo-list" ] <|
            List.map (viewKeyedEntry app) (List.filter isVisible entries)
        ]


toggleAllForm : Form.HtmlForm String Action input Msg
toggleAllForm =
    Form.init
        (\toggleTo ->
            { combine =
                Validation.succeed CheckAll
                    |> Validation.andMap toggleTo
            , view =
                \formState ->
                    [ button
                        [ class "toggle-all"
                        , name "toggle"

                        --, checked allCompleted
                        ]
                        [ text "❯" ]
                    , label
                        [ for "toggle-all" ]
                        [ text "Mark all as complete" ]
                    ]
            }
        )
        |> Form.hiddenField "toggleTo"
            (Field.checkbox
                |> Field.withInitialValue
                    (\_ ->
                        Form.Value.bool
                            -- TODO remove hardcoding
                            --, onClick (CheckAll (not allCompleted))
                            True
                    )
            )
        |> Form.hiddenKind ( "kind", "toggle-all" ) "Expected kind"



-- VIEW INDIVIDUAL ENTRIES


viewKeyedEntry : StaticPayload Data ActionData RouteParams -> Todo -> ( String, Html (Pages.Msg.Msg Msg) )
viewKeyedEntry app todo =
    ( uuidToString todo.id, lazy2 viewEntry app todo )


viewEntry : StaticPayload Data ActionData RouteParams -> { description : String, completed : Bool, id : Uuid } -> Html (Pages.Msg.Msg Msg)
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
                |> Form.renderHtml []
                    Nothing
                    app
                    todo
            , editItemForm
                |> Form.toDynamicFetcher ("edit-" ++ uuidToString todo.id)
                |> Form.renderHtml []
                    Nothing
                    app
                    todo
            , if uuidToString todo.id == "" then
                Html.text ""

              else
                deleteItemForm
                    |> Form.toDynamicFetcher ("delete-" ++ uuidToString todo.id)
                    |> Form.renderHtml []
                        Nothing
                        app
                        todo
            ]
        ]


editItemForm : Form.HtmlForm String Action Todo Msg
editItemForm =
    Form.init
        (\itemId description ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap itemId
                    |> Validation.andMap description
                    |> Validation.map UpdateEntry
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


uuidToString : Uuid -> String
uuidToString (Uuid uuid) =
    uuid



-- VIEW CONTROLS AND FOOTER


viewControls : StaticPayload Data ActionData RouteParams -> Visibility -> List Todo -> Html (Pages.Msg.Msg Msg)
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
        [ visibilitySwap "/" All visibility
        , text " "
        , visibilitySwap "/active" Active visibility
        , text " "
        , visibilitySwap "/completed" Completed visibility
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


visibilitySwap : String -> Visibility -> Visibility -> Html (Pages.Msg.Msg Msg)
visibilitySwap uri visibility actualVisibility =
    li
        []
        [ a [ href uri, classList [ ( "selected", visibility == actualVisibility ) ] ]
            [ visibility |> visibilityToString |> text ]
        ]


viewControlsClear : StaticPayload Data ActionData RouteParams -> Int -> Html (Pages.Msg.Msg Msg)
viewControlsClear app entriesCompleted =
    clearCompletedForm
        |> Form.toDynamicFetcher "clear-completed"
        |> Form.renderHtml [] Nothing app ()


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


completeIcon : Html msg
completeIcon =
    Svg.svg
        [ SvgAttr.width "40"
        , SvgAttr.height "40"
        , SvgAttr.viewBox "-10 -18 100 135"
        ]
        [ Svg.circle
            [ SvgAttr.cx "50"
            , SvgAttr.cy "50"
            , SvgAttr.r "50"
            , SvgAttr.fill "none"
            , SvgAttr.stroke "#bddad5"
            , SvgAttr.strokeWidth "3"
            ]
            []
        , Svg.path
            [ SvgAttr.fill "#5dc2af"
            , SvgAttr.d "M72 25L42 71 27 56l-4 4 20 20 34-52z"
            ]
            []
        ]


incompleteIcon : Html msg
incompleteIcon =
    Svg.svg
        [ SvgAttr.width "40"
        , SvgAttr.height "40"
        , SvgAttr.viewBox "-10 -18 100 135"
        ]
        [ Svg.circle
            [ SvgAttr.cx "50"
            , SvgAttr.cy "50"
            , SvgAttr.r "50"
            , SvgAttr.fill "none"
            , SvgAttr.stroke "#ededed"
            , SvgAttr.strokeWidth "3"
            ]
            []
        ]
