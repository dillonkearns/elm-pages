module Route.Todos exposing (ActionData, Data, Model, Msg, route)

import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.Todo
import Api.Object.TodoPage
import Api.Query
import Api.Scalar exposing (Id(..))
import DataSource exposing (DataSource)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form exposing (Form)
import Form.Value
import FormDecoder exposing (FormData)
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet as SelectionSet
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import List.Extra
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Fauna
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
import Server.Response as Response exposing (Response)
import Set exposing (Set)
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type Msg
    = FormMsg Form.Msg
    | NoOp
    | FormSubmitted FormData
    | DeleteFormSubmitted String FormData


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
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        FormMsg formMsg ->
            ( model, Effect.none )

        NoOp ->
            -- TODO would be nice to have a `Maybe msg` for `SubmitFetcher` to avoid the NoOp Msg
            ( model, Effect.none )

        FormSubmitted { fields } ->
            ( model
            , Effect.SubmitFetcher
                (static.submit
                    { fields = fields, headers = [] }
                )
                |> Effect.map (\_ -> NoOp)
            )

        DeleteFormSubmitted id { fields } ->
            ( model
            , Effect.SubmitFetcher
                (static.submit
                    { fields = fields, headers = [] }
                )
                |> Effect.map (\_ -> NoOp)
            )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    { todos : List Todo
    }


type alias ActionData =
    Maybe Form.Model


type alias Todo =
    { description : String
    , id : String
    }


type alias TodoInput =
    { description : String }


todos : SelectionSet.SelectionSet (List Todo) RootQuery
todos =
    Api.Query.allTodos identity
        (Api.Object.TodoPage.data todoSelection
            |> SelectionSet.nonNullElementsOrFail
        )


createTodo : String -> SelectionSet.SelectionSet Todo RootMutation
createTodo description =
    Api.Mutation.createTodo
        { data =
            Api.InputObject.buildTodoInput
                { description = description
                , completed = False
                }
        }
        todoSelection


deleteTodo : String -> SelectionSet.SelectionSet () RootMutation
deleteTodo id =
    Api.Mutation.deleteTodo { id = Id id }
        (Api.Object.Todo.id_ |> SelectionSet.map (\_ -> ()))
        |> SelectionSet.map (Maybe.withDefault ())


todoSelection : SelectionSet.SelectionSet Todo Api.Object.Todo
todoSelection =
    SelectionSet.map2 Todo
        Api.Object.Todo.description
        (Api.Object.Todo.id_ |> SelectionSet.map (\(Id id) -> id))


data : RouteParams -> Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.requestTime
            |> Request.map
                (\time ->
                    Request.Fauna.dataSource (time |> Time.posixToMillis |> String.fromInt) todos
                        |> DataSource.map Data
                        |> DataSource.map Response.render
                )
        ]


action : RouteParams -> Parser (DataSource (Response ActionData ErrorPage))
action _ =
    Request.oneOf
        [ Form.submitHandlers (deleteItemForm "")
            (\model decoded ->
                case decoded of
                    Ok id ->
                        Request.Fauna.mutationDataSource "" (deleteTodo id)
                            |> DataSource.map
                                (\_ -> Route.redirectTo Route.Todos)

                    Err error ->
                        Nothing
                            |> Response.render
                            |> DataSource.succeed
            )
        , Form.submitHandlers (newItemForm False)
            (\model decoded ->
                case decoded of
                    Ok okItem ->
                        Request.Fauna.mutationDataSource "" (createTodo okItem.description)
                            |> DataSource.map
                                (\_ ->
                                    --Route.redirectTo Route.Todos
                                    Response.render Nothing
                                )

                    Err error ->
                        model
                            |> Just
                            |> Response.render
                            |> DataSource.succeed
            )
        ]


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Full-stack elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Full-stack elm-pages Todo App demo"
        , locale = Nothing
        , title = "elm-pages Todo App"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model static =
    let
        deleting : Set String
        deleting =
            static.fetchers
                |> List.filterMap
                    (\fetcher ->
                        case fetcher.payload.fields of
                            [ ( "id", deletingItemId ) ] ->
                                Just deletingItemId

                            _ ->
                                Nothing
                    )
                |> Set.fromList

        submittingItem : Maybe String
        submittingItem =
            static.fetchers
                |> List.Extra.findMap
                    (\fetcher ->
                        case fetcher.payload.fields of
                            [ ( "description", newItemDescription ) ] ->
                                Just newItemDescription

                            _ ->
                                Nothing
                    )

        submitting : Bool
        submitting =
            case submittingItem of
                Just _ ->
                    True

                Nothing ->
                    False
    in
    { title = "Todos"
    , body =
        [ Html.pre []
            [ static.fetchers
                |> Debug.toString
                |> Html.text
            ]
        , Html.ul []
            ((static.data.todos
                |> List.map
                    (\item ->
                        Html.li
                            (if deleting |> Set.member item.id then
                                [ Attr.style "opacity" "0.5"
                                ]

                             else
                                []
                            )
                            [ Html.text item.description
                            , deleteItemForm item.id
                                |> Form.toStatelessHtml
                                    (Just (DeleteFormSubmitted item.id))
                                    Html.form
                                    (Form.init (deleteItemForm item.id))
                            ]
                    )
             )
                ++ (case submittingItem of
                        Nothing ->
                            []

                        Just pendingNewItem ->
                            [ Html.li
                                [ Attr.style "opacity" "0.5"
                                ]
                                [ Html.text pendingNewItem
                                ]
                            ]
                   )
            )
        , errorsView static.action
        , newItemForm submitting
            |> Form.toStatelessHtml
                (Just FormSubmitted)
                Html.form
                (Form.init (newItemForm submitting))
        ]
    }


errorsView : Maybe ActionData -> Html msg
errorsView actionData =
    case actionData |> Maybe.andThen identity of
        Just justData ->
            justData
                |> Form.getErrors
                |> List.map (\( name, error ) -> Html.text (name ++ ": " ++ error))
                |> Html.ul [ Attr.style "color" "red" ]

        Nothing ->
            Html.div [] []


newItemForm : Bool -> Form (Pages.Msg.Msg Msg) String TodoInput (Html (Pages.Msg.Msg Msg))
newItemForm submitting =
    Form.succeed (\description () -> TodoInput description)
        |> Form.with
            (Form.text "description"
                (\info ->
                    Html.div []
                        [ Html.label info.toLabel
                            [ Html.text "Description"
                            ]
                        , Html.input (Attr.autofocus True :: info.toInput) []
                        ]
                )
                |> Form.required "Required"
            )
        |> Form.with
            (Form.submit
                (\{ attrs } ->
                    Html.button attrs
                        [ Html.text
                            (if submitting then
                                "Submitting..."

                             else
                                "Submit"
                            )
                        ]
                )
            )


deleteItemForm : String -> Form (Pages.Msg.Msg Msg) String String (Html (Pages.Msg.Msg Msg))
deleteItemForm id =
    Form.succeed
        (\id_ _ -> id_)
        |> Form.with
            (Form.hidden "id"
                id
                (\attrs ->
                    Html.input attrs []
                )
                |> Form.withInitialValue (Form.Value.string id)
            )
        |> Form.with
            (Form.submit
                (\{ attrs } ->
                    Html.button attrs
                        [ Html.text "X" ]
                )
            )
