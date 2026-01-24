module Route.GetForm exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
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
import Html.Styled
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias Filters =
    { page : Int
    }


form : Form.HtmlForm String Filters Filters (PagesMsg Msg)
form =
    Form.form
        (\page ->
            { combine =
                Validation.succeed Filters
                    |> Validation.andMap page
            , view =
                \formState ->
                    [ page
                        |> Form.FieldView.valueButton "1"
                            []
                            [ Html.text "Page 1" ]
                    , page
                        |> Form.FieldView.valueButton "2"
                            []
                            [ Html.text "Page 2" ]
                    ]
            }
        )
        |> Form.field "page"
            (Field.int { invalid = \_ -> "" }
                |> Field.map (Maybe.withDefault 1)
             --|> Field.withInitialValue .first
            )


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { filters : Filters
    }


data : RouteParams -> Request -> BackendTask FatalError (Server.Response.Response Data ErrorPage)
data routeParams request =
    case request |> Request.formData (Form.Handler.init identity form) of
        Nothing ->
            Data { page = 1 }
                |> Server.Response.render
                |> BackendTask.succeed

        Just ( formResponse, formResult ) ->
            case formResult of
                Form.Valid filters ->
                    Data filters
                        |> Server.Response.render
                        |> BackendTask.succeed

                Form.Invalid _ _ ->
                    Data { page = 1 }
                        |> Server.Response.render
                        |> BackendTask.succeed


action : RouteParams -> Request -> BackendTask FatalError (Server.Response.Response ActionData ErrorPage)
action routeParams request =
    Server.Response.render {}
        |> BackendTask.succeed


head :
    App Data () ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "GET Form Example"
    , body =
        [ form
            |> Pages.Form.renderHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                (Form.options "user-form"
                    |> Form.withInput app.data.filters
                    |> Form.withGetMethod
                )
                app
        , Html.h2 []
            [ Html.text <| "Current page: " ++ String.fromInt app.data.filters.page
            ]
        ]
            |> List.map Html.Styled.fromUnstyled
    }
