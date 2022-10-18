module Route.Fetcher exposing (ActionData, Data, Model, Msg, RouteParams, route)

{-| -}

import DataSource
import DataSource.Port
import Effect
import ErrorPage
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Validation as Validation
import Html.Styled as Html
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Msg
import Pages.PageUrl
import Platform.Sub
import RouteBuilder
import Server.Request
import Server.Response
import View


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.buildWithLocalState
        { view = view
        , init = init
        , update = update
        , subscriptions = \_ _ _ _ _ -> Platform.Sub.none
        }
        (RouteBuilder.serverRender { data = data, action = action, head = \_ -> [] })


init :
    Maybe Pages.PageUrl.PageUrl
    -> sharedModel
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> ( {}, Effect.Effect Msg )
init pageUrl sharedModel app =
    ( {}, Effect.none )


update :
    Pages.PageUrl.PageUrl
    -> sharedModel
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect.Effect Msg )
update pageUrl sharedModel app msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


type alias Data =
    { items : List String
    }


type alias ActionData =
    {}


data :
    RouteParams
    -> Server.Request.Parser (DataSource.DataSource (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed
        (DataSource.Port.get "getItems"
            Encode.null
            (Decode.list Decode.string)
            |> DataSource.map
                (\items ->
                    Server.Response.render
                        { items = items
                        }
                )
        )


type Action
    = AddItem String
    | DeleteAll


action :
    RouteParams
    -> Server.Request.Parser (DataSource.DataSource (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.formData
        (form
            |> Form.initCombined AddItem
            |> Form.combine (\() -> DeleteAll) deleteForm
        )
        |> Server.Request.map
            (\formPost ->
                case formPost of
                    Ok (AddItem newItem) ->
                        DataSource.Port.get "addItem"
                            (Encode.string newItem)
                            (Decode.list Decode.string)
                            |> DataSource.map
                                (\_ ->
                                    Server.Response.render ActionData
                                )

                    Ok DeleteAll ->
                        DataSource.Port.get "deleteAllItems"
                            Encode.null
                            (Decode.list Decode.string)
                            |> DataSource.map
                                (\_ ->
                                    Server.Response.render ActionData
                                )

                    Err _ ->
                        DataSource.succeed
                            (Server.Response.render ActionData)
            )


form : Form.StyledHtmlForm String String () Msg
form =
    Form.init
        (\name ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap name
            , view =
                \info ->
                    [ name |> FieldView.inputStyled []
                    , Html.button []
                        [ Html.text "Submit"
                        ]
                    ]
            }
        )
        |> Form.field "name" (Field.text |> Field.required "Required")


deleteForm : Form.StyledHtmlForm String () () Msg
deleteForm =
    Form.init
        { combine =
            Validation.succeed ()
        , view =
            \info ->
                [ Html.button []
                    [ Html.text "Delete All"
                    ]
                ]
        }
        |> Form.hiddenKind ( "kind", "delete-all" ) "Expected kind"


view :
    Maybe Pages.PageUrl.PageUrl
    -> sharedModel
    -> Model
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> View.View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Fetcher Example"
    , body =
        [ Html.div []
            [ form
                |> Form.toDynamicFetcher "add-item"
                |> Form.renderStyledHtml [] Nothing app ()
            ]
        , Html.div []
            [ deleteForm
                |> Form.toDynamicFetcher "delete-all"
                |> Form.renderStyledHtml [] Nothing app ()
            ]
        , app.data.items
            |> List.map
                (\item ->
                    Html.li [] [ Html.text item ]
                )
            |> Html.ul []
        ]
    }
