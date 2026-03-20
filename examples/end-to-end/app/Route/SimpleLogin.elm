module Route.SimpleLogin exposing (ActionData, Data, Model, Msg, route)

{-| Simple login route that redirects to /counter on submission.
Demonstrates the action redirect pattern.
-}

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation
import Html.Styled as Html
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \_ -> []
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.succeed (Response.render {})


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    -- On any form submission, redirect to /counter
    Route.redirectTo Route.Counter
        |> BackendTask.succeed


form : Form.StyledHtmlForm String (Maybe String) input msg
form =
    Form.form
        (\username ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap username
            , view =
                \formState ->
                    [ Html.div []
                        [ Html.label []
                            [ Html.text "Username: "
                            , username |> Form.FieldView.inputStyled []
                            ]
                        ]
                    , Html.button []
                        [ Html.text "Log In" ]
                    ]
            }
        )
        |> Form.field "username" Field.text


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Login"
    , body =
        [ Html.h1 [] [ Html.text "Simple Login" ]
        , Html.p [] [ Html.text "Enter any username to log in" ]
        , form
            |> Pages.Form.renderStyledHtml []
                (Form.options "login-form")
                app
        ]
    }
