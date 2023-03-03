module Route.GetForm exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Styled
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Parser)
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


form : Form.HtmlForm String Filters Filters Msg
form =
    Form.init
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
             --|> Field.withInitialValue (.first >> Form.Value.string)
            )


route : StatelessRoute RouteParams Data ActionData
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


data : RouteParams -> Parser (BackendTask FatalError (Server.Response.Response Data ErrorPage))
data routeParams =
    Request.formData (Form.initCombined identity form)
        |> Request.map
            (\( formResponse, formResult ) ->
                case formResult of
                    Ok filters ->
                        Data filters
                            |> Server.Response.render
                            |> BackendTask.succeed

                    Err _ ->
                        Data { page = 1 }
                            |> Server.Response.render
                            |> BackendTask.succeed
            )


action : RouteParams -> Parser (BackendTask FatalError (Server.Response.Response ActionData ErrorPage))
action routeParams =
    Request.succeed
        (Server.Response.render {}
            |> BackendTask.succeed
        )


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "GET Form Example"
    , body =
        [ form
            |> Form.toDynamicTransition "user-form"
            |> Form.withGetMethod
            |> Form.renderHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                (\_ -> Nothing)
                app
                app.data.filters
        , Html.h2 []
            [ Html.text <| "Current page: " ++ String.fromInt app.data.filters.page
            ]
        ]
            |> List.map Html.Styled.fromUnstyled
    }
