module Route.Fetcher exposing (ActionData, Data, Model, Msg, RouteParams, route)

{-| -}

import DataSource exposing (DataSource)
import DataSource.Port
import Dict
import Effect
import ErrorPage
import Exception exposing (Throwable)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Validation as Validation
import Html.Styled as Html
import Html.Styled.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Msg
import Pages.PageUrl
import Pages.Transition exposing (FetcherSubmitStatus(..))
import Platform.Sub
import RouteBuilder
import Server.Request
import Server.Response
import View


type alias Model =
    { itemIndex : Int
    }


type Msg
    = NoOp
    | AddItemSubmitted


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
    -> ( Model, Effect.Effect Msg )
init pageUrl sharedModel app =
    ( { itemIndex = 0
      }
    , Effect.none
    )


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

        AddItemSubmitted ->
            ( { model
                | itemIndex = model.itemIndex + 1
              }
            , Effect.none
            )


type alias Data =
    { items : List String
    }


type alias ActionData =
    {}


data :
    RouteParams
    -> Server.Request.Parser (DataSource Throwable (Server.Response.Response Data ErrorPage.ErrorPage))
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
    -> Server.Request.Parser (DataSource Throwable (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.formData
        forms
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


forms : Form.ServerForms String Action
forms =
    form
        |> Form.initCombined AddItem
        |> Form.combine (\() -> DeleteAll) deleteForm


form : Form.StyledHtmlForm String String () Msg
form =
    Form.init
        (\name ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap name
            , view =
                \info ->
                    [ name |> FieldView.inputStyled [ Attr.autofocus True ]
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
    let
        inFlight : List Action
        inFlight =
            app.fetchers
                |> Dict.values
                |> List.filterMap
                    (\{ status, payload } ->
                        case status of
                            FetcherComplete _ ->
                                Nothing

                            _ ->
                                forms
                                    |> Form.runOneOfServerSide payload.fields
                                    |> Tuple.first
                    )

        creatingItems : List String
        creatingItems =
            inFlight
                |> List.filterMap
                    (\fetcher ->
                        case fetcher of
                            AddItem name ->
                                Just name

                            _ ->
                                Nothing
                    )

        optimisticItems : List Status
        optimisticItems =
            (app.data.items |> List.map Created)
                ++ (creatingItems |> List.map Pending)
    in
    { title = "Fetcher Example"
    , body =
        [ Html.p []
            [ Html.text <| String.fromInt model.itemIndex ]
        , form
            |> Form.toDynamicFetcher ("add-item-" ++ String.fromInt model.itemIndex)
            |> Form.withOnSubmit (\_ -> AddItemSubmitted)
            |> Form.renderStyledHtml [] Nothing app ()
        , Html.div []
            [ deleteForm
                |> Form.toDynamicFetcher "delete-all"
                |> Form.renderStyledHtml [] Nothing app ()
            ]
        , optimisticItems
            |> List.map
                (\item ->
                    case item of
                        Pending name ->
                            Html.li [ Attr.class "loading" ] [ Html.text <| name ++ "..." ]

                        Created name ->
                            Html.li [] [ Html.text name ]
                )
            |> Html.ul [ Attr.id "items" ]
        , Html.p []
            [ if inFlight |> List.member DeleteAll then
                Html.text "Deleting..."

              else
                Html.text "Ready"
            ]
        , app.fetchers
            |> Dict.toList
            |> List.map
                (\( key, item ) ->
                    Html.li []
                        [ Html.text <| Debug.toString item
                        ]
                )
            |> Html.ul []
        ]
    }


type Status
    = Pending String
    | Created String
