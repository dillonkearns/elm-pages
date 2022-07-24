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
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Validation)
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
    Request.formDataWithoutServerValidation [ deleteForm, createForm ]
        |> Request.map
            (\actionResult ->
                case actionResult of
                    Ok (Delete { id }) ->
                        Request.Fauna.mutationDataSource "" (deleteTodo id)
                            |> DataSource.map
                                (\_ -> Route.redirectTo Route.Todos)

                    Ok (Create { description }) ->
                        Request.Fauna.mutationDataSource "" (createTodo description)
                            |> DataSource.map
                                (\_ ->
                                    --Route.redirectTo Route.Todos
                                    Response.render {}
                                )

                    Err error ->
                        {} |> Response.render |> DataSource.succeed
            )


type Action
    = Delete { id : String }
    | Create { description : String }


deleteForm : Form.HtmlForm String Action String msg
deleteForm =
    Form.init
        (\id ->
            { combine =
                Validation.succeed (\i -> Delete { id = i })
                    |> Validation.andMap id
            , view =
                \info ->
                    [ Html.button [] [ Html.text "❌" ]
                    ]
            }
        )
        |> Form.hiddenField "id" (Field.text |> Field.required "Required" |> Field.withInitialValue Form.Value.string)


createForm : Form.HtmlForm String Action data msg
createForm =
    Form.init
        (\query ->
            { combine =
                Validation.succeed (\d -> Create { description = d })
                    |> Validation.andMap query
            , view =
                \info ->
                    [ query |> descriptionFieldView info
                    , Html.button []
                        [ Html.text <|
                            -- TODO retain isTransitioning state while refetching `data` after a submission
                            if info.isTransitioning then
                                "Creating..."

                            else
                                "Create"
                        ]
                    ]
            }
        )
        |> Form.field "q" (Field.text |> Field.required "Required")


descriptionFieldView :
    Form.Context String data
    -> Validation String parsed Form.FieldView.Input
    -> Html msg
descriptionFieldView formState field =
    Html.div []
        [ Html.label []
            [ Html.text "Description "
            , field |> Form.FieldView.input [ Attr.autofocus True ]
            ]
        , errorsForField formState field
        ]


errorsForField : Form.Context String data -> Validation String parsed kind -> Html msg
errorsForField formState field =
    (if True then
        formState.errors
            |> Form.errorsForField field
            |> List.map (\error -> Html.li [] [ Html.text error ])

     else
        []
    )
        |> Html.ul [ Attr.style "color" "red" ]


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
                            , deleteForm
                                |> Form.toDynamicTransition "test1"
                                |> Form.renderHtml
                                    [ Attr.style "display" "inline"
                                    , Attr.style "padding-left" "6px"
                                    ]
                                    -- TODO pass in server data
                                    Nothing
                                    static
                                    item.id
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
        , createForm
            |> Form.toDynamicTransition "test2"
            |> Form.renderHtml []
                -- TODO pass in server data
                Nothing
                static
                ()
        ]
    }
