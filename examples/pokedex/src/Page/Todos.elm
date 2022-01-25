module Page.Todos exposing (Data, Model, Msg, page)

import Api.InputObject
import Api.Mutation
import Api.Object.Todo
import Api.Object.TodoPage
import Api.Query
import Api.Scalar exposing (Id(..))
import Browser.Navigation
import DataSource exposing (DataSource)
import Form exposing (Form)
import Form.Value
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet as SelectionSet
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Page exposing (Page, PageWithState, StaticPayload)
import Pages
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Fauna
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import Time
import Url
import View exposing (View)


type alias Model =
    {}


type Msg
    = FormMsg Form.Msg
    | NoOp
    | MakeHttpRequest (List ( String, String ))
    | ReloadPage


type alias RouteParams =
    {}


page : PageWithState RouteParams Data Model Msg
page =
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> ( Model, Cmd Msg )
init maybePageUrl sharedModel static =
    ( {}, Cmd.none )


update :
    PageUrl
    -> Maybe Browser.Navigation.Key
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> Msg
    -> Model
    -> ( Model, Cmd Msg )
update pageUrl maybeNavigationKey sharedModel static msg model =
    case msg of
        FormMsg formMsg ->
            ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )

        ReloadPage ->
            ( model
            , Pages.reloadData
            )

        MakeHttpRequest items ->
            ( model
            , Http.request
                { method = "POST"
                , headers =
                    [--Http.header "accept" "TODO which format?"
                    ]
                , body =
                    items
                        |> List.map
                            (\( name, value ) ->
                                Url.percentEncode name ++ "=" ++ Url.percentEncode value
                            )
                        |> String.join "&"
                        |> Http.stringBody "application/x-www-form-urlencoded"
                , expect =
                    -- TODO how should this be decoded? Only check for errors? Or custom Ok response decoding?
                    -- Should the error response give back a Form.Model?
                    Http.expectWhatever (\_ -> ReloadPage)

                --Http.expectJson identity
                --    (Decode.dict
                --        (Decode.map2
                --            (\raw errors ->
                --                { raw = raw
                --                , errors = errors
                --                , status = NotVisited
                --                }
                --            )
                --            (Decode.field "raw" (Decode.nullable Decode.string))
                --            (Decode.field "errors" (Decode.list Decode.string))
                --        )
                --    )
                , timeout = Nothing
                , tracker = Nothing
                , url = "/todos"
                }
            )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    { todos : List Todo
    }


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


todoSelection =
    SelectionSet.map2 Todo
        Api.Object.Todo.description
        (Api.Object.Todo.id_ |> SelectionSet.map (\(Id id) -> id))


data : RouteParams -> Request (DataSource (Response Data))
data routeParams =
    Request.oneOf
        [ Form.submitHandlers2 (deleteItemForm "")
            (\model decoded ->
                case decoded of
                    Ok id ->
                        Request.Fauna.mutationDataSource "" (deleteTodo id)
                            |> DataSource.map
                                (\_ ->
                                    Response.temporaryRedirect "/todos"
                                )

                    Err error ->
                        { todos =
                            [ { description = Debug.toString model
                              , id = ""
                              }
                            ]
                        }
                            |> Response.render
                            |> DataSource.succeed
            )
        , Form.submitHandlers2 newItemForm
            (\model decoded ->
                case decoded of
                    Ok okItem ->
                        Request.Fauna.mutationDataSource "" (createTodo okItem.description)
                            |> DataSource.map
                                (\_ ->
                                    Response.temporaryRedirect "/todos"
                                )

                    Err error ->
                        { todos =
                            [ { description = Debug.toString model
                              , id = ""
                              }
                            ]
                        }
                            |> Response.render
                            |> DataSource.succeed
            )
        , Request.requestTime
            |> Request.map
                (\time ->
                    Request.Fauna.dataSource (time |> Time.posixToMillis |> String.fromInt) todos
                        |> DataSource.map Data
                        |> DataSource.map Response.render
                )
        ]


head :
    StaticPayload Data RouteParams
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
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel model static =
    { title = "Todos"
    , body =
        [ Html.ul []
            (static.data.todos
                |> List.map
                    (\item ->
                        Html.li []
                            [ Html.text item.description
                            , deleteItemForm item.id
                                |> Form.toHtml2
                                    { makeHttpRequest = MakeHttpRequest }
                                    Html.form
                                    (Form.init (deleteItemForm item.id))
                            ]
                    )
            )
        , newItemForm
            |> Form.toHtml2
                { makeHttpRequest = MakeHttpRequest }
                Html.form
                (Form.init newItemForm)
        ]
    }


newItemForm : Form String TodoInput (Html Msg)
newItemForm =
    Form.succeed (\description () -> TodoInput description)
        |> Form.with
            (Form.text "description"
                (\{ toInput } ->
                    Html.input (Attr.autofocus True :: toInput) []
                        |> Html.map (\_ -> NoOp)
                )
                |> Form.required "Required"
            )
        |> Form.with
            (Form.submit
                (\{ attrs } ->
                    Html.button attrs [ Html.text "Submit" ]
                        |> Html.map (\_ -> NoOp)
                )
            )


deleteItemForm : String -> Form String String (Html Msg)
deleteItemForm id =
    Form.succeed
        (\id_ _ -> id_)
        |> Form.with
            (Form.hidden "id"
                id
                (\attrs ->
                    Html.input attrs []
                        |> Html.map (\_ -> NoOp)
                )
                |> Form.withInitialValue (Form.Value.string id)
            )
        |> Form.with
            (Form.submit
                (\{ attrs } ->
                    Html.button attrs
                        [ Html.text "X" ]
                        |> Html.map (\_ -> NoOp)
                )
            )
