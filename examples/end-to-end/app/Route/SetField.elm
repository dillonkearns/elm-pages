module Route.SetField exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Html.Styled
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    {}


type Msg
    = SetSuggestion


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias StaticData =
    ()


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
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init app sharedModel =
    ( {}, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        SetSuggestion ->
            ( model
            , Effect.SetField
                { formId = "set-field-form"
                , name = "name"
                , value = "Suggested Value"
                }
            )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


data :
    RouteParams
    -> Request
    -> BackendTask FatalError (Server.Response.Response Data ErrorPage)
data routeParams request =
    BackendTask.succeed (Server.Response.render {})


action :
    RouteParams
    -> Request
    -> BackendTask FatalError (Server.Response.Response ActionData ErrorPage)
action routeParams request =
    BackendTask.succeed (Server.Response.render {})


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    []


nameForm : Form.HtmlForm String String () (PagesMsg Msg)
nameForm =
    Form.form
        (\name ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap name
            , view =
                \formState ->
                    let
                        fieldView : String -> Validation.Field String parsed Form.FieldView.Input -> Html msg
                        fieldView label field =
                            Html.div []
                                [ Html.label []
                                    [ Html.text (label ++ " ")
                                    , field |> Form.FieldView.input [ Attr.attribute "data-testid" "name-input" ]
                                    ]
                                ]
                    in
                    [ fieldView "Name" name
                    ]
            }
        )
        |> Form.field "name"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\_ -> "")
            )


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "SetField Test"
    , body =
        [ Html.h1 [] [ Html.text "SetField Test" ]
        , Html.button
            [ Html.Events.onClick (PagesMsg.fromMsg SetSuggestion)
            , Attr.attribute "data-testid" "set-field-button"
            ]
            [ Html.text "Set Suggestion" ]
        , nameForm
            |> Pages.Form.renderHtml []
                (Form.options "set-field-form"
                    |> Form.withInput ()
                )
                app
        ]
            |> List.map Html.Styled.fromUnstyled
    }
