module Route.Fetcher exposing (ActionData, Data, Model, Msg, RouteParams, route)

{-| -}

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Dict
import Effect
import ErrorPage
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Handler
import Form.Validation as Validation
import Html.Styled as Html
import Html.Styled.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Form
import Pages.Transition exposing (FetcherSubmitStatus(..))
import PagesMsg exposing (PagesMsg)
import Platform.Sub
import RouteBuilder
import Server.Request
import Server.Response
import Shared
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
        , subscriptions = \_ _ _ _ -> Platform.Sub.none
        }
        (RouteBuilder.serverRender { data = data, action = action, head = \_ -> [] })


init :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect.Effect Msg )
init app shared =
    ( { itemIndex = 0
      }
    , Effect.none
    )


update :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect.Effect Msg )
update app shared msg model =
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
    -> Server.Request.Parser (BackendTask FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed
        (BackendTask.Custom.run "getItems"
            Encode.null
            (Decode.list Decode.string)
            |> BackendTask.allowFatal
            |> BackendTask.map
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
    -> Server.Request.Parser (BackendTask FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.formData
        forms
        |> Server.Request.map
            (\( formResponse, formPost ) ->
                case formPost of
                    Form.Valid (AddItem newItem) ->
                        BackendTask.Custom.run "addItem"
                            (Encode.string newItem)
                            (Decode.list Decode.string)
                            |> BackendTask.allowFatal
                            |> BackendTask.map
                                (\_ ->
                                    Server.Response.render ActionData
                                )

                    Form.Valid DeleteAll ->
                        BackendTask.Custom.run "deleteAllItems"
                            Encode.null
                            (Decode.list Decode.string)
                            |> BackendTask.allowFatal
                            |> BackendTask.map
                                (\_ ->
                                    Server.Response.render ActionData
                                )

                    Form.Invalid _ _ ->
                        BackendTask.succeed
                            (Server.Response.render ActionData)
            )


forms : Form.Handler.Handler String Action
forms =
    form
        |> Form.Handler.init AddItem
        |> Form.Handler.with (\() -> DeleteAll) deleteForm


form : Form.StyledHtmlForm String String () (PagesMsg Msg)
form =
    Form.form
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


deleteForm : Form.StyledHtmlForm String () () (PagesMsg Msg)
deleteForm =
    Form.form
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
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View.View (PagesMsg Msg)
view app sharedModel model =
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
                                    |> Form.Handler.run payload.fields
                                    |> Form.toResult
                                    |> Result.toMaybe
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
            |> Pages.Form.renderStyledHtml
                []
                Pages.Form.Serial
                (Form.options ("add-item-" ++ String.fromInt model.itemIndex)
                    |> Form.withOnSubmit (\_ -> AddItemSubmitted)
                )
                app
        , Html.div []
            [ deleteForm
                |> Pages.Form.renderStyledHtml
                    []
                    Pages.Form.Parallel
                    (Form.options "delete-all")
                    app
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
