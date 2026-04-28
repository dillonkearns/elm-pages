module Route.New exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Handler
import Form.Validation as Validation
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import MySession
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import UrlPath exposing (UrlPath)
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
update app sharedModel msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type alias ActionData =
    {}


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.succeed (Response.render Data)


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    -- TODO: re-implement with file-based data layer
    -- Original: parsed form, called Smoothies.create, redirected to Index
    BackendTask.succeed (Response.render {})


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    []


form : Form.StyledHtmlForm String NewItem data msg
form =
    Form.form
        (\name description price imageUrl ->
            { combine =
                Validation.succeed NewItem
                    |> Validation.andMap name
                    |> Validation.andMap description
                    |> Validation.andMap price
                    |> Validation.andMap imageUrl
            , view =
                \info ->
                    let
                        errors field =
                            info.errors
                                |> Form.errorsForField field

                        errorsView field =
                            (if True then
                                errors field
                                    |> List.map (\error -> Html.li [] [ Html.text error ])

                             else
                                []
                            )
                                |> Html.ul [ Attr.style "color" "red" ]

                        fieldView label field =
                            Html.div []
                                [ Html.label []
                                    [ Html.text (label ++ " ")
                                    , field |> FieldView.inputStyled []
                                    ]
                                , errorsView field
                                ]
                    in
                    [ fieldView "Name" name
                    , fieldView "Description" description
                    , fieldView "Price" price
                    , fieldView "Image" imageUrl
                    , Html.button [] [ Html.text "Create" ]
                    ]
            }
        )
        |> Form.field "name" (Field.text |> Field.required "Required")
        |> Form.field "description"
            (Field.text
                |> Field.required "Required"
                |> Field.validateMap
                    (\description ->
                        if (description |> String.length) < 5 then
                            Err "Description must be at least 5 characters"

                        else
                            Ok description
                    )
            )
        |> Form.field "price" (Field.int { invalid = \_ -> "Invalid int" } |> Field.required "Required")
        |> Form.field "imageUrl" (Field.text |> Field.required "Required")


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "New Item"
    , body =
        [ Html.h2 [] [ Html.text "New item" ]
        , form
            |> Pages.Form.renderStyledHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                (Form.options "form")
                app
        ]
    }


type alias NewItem =
    { name : String, description : String, price : Int, imageUrl : String }
