module Route.DarkMode exposing (ActionData, Data, Model, Msg, RouteParams, route)

import BackendTask exposing (BackendTask)
import Css
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.Handler
import Form.Validation as Validation
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes exposing (css)
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : RouteBuilder.StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.buildNoState
        { view = view
        }
        (RouteBuilder.serverRender { data = data, action = action, head = head })


type alias Data =
    { isDarkMode : Bool
    }


type alias ActionData =
    { formResponse : Form.ServerResponse String }


sessionOptions =
    { name = "darkMode"
    , secrets = BackendTask.succeed [ "test" ]
    , options = Nothing
    }


data :
    RouteParams
    -> Request
    -> BackendTask FatalError (Response Data ErrorPage.ErrorPage)
data routeParams request =
    request
        |> Session.withSession sessionOptions
            (\session ->
                let
                    isDarkMode : Bool
                    isDarkMode =
                        (session |> Session.get "darkMode") == Just "dark"
                in
                BackendTask.succeed
                    ( session
                    , Response.render
                        { isDarkMode = isDarkMode
                        }
                    )
            )


action :
    RouteParams
    -> Request
    -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    request
        |> Session.withSessionResult sessionOptions
            (\sessionResult ->
                case request |> Request.formData (form |> Form.Handler.init identity) of
                    Nothing ->
                        "Expected form submission." |> FatalError.fromString |> BackendTask.fail

                    Just ( response, formPost ) ->
                        let
                            setToDarkMode : Bool
                            setToDarkMode =
                                case formPost of
                                    Form.Valid ok ->
                                        ok

                                    Form.Invalid _ _ ->
                                        False

                            session : Session.Session
                            session =
                                sessionResult
                                    |> Result.withDefault Session.empty
                        in
                        BackendTask.succeed
                            ( session
                                |> Session.insert "darkMode"
                                    (if setToDarkMode then
                                        "dark"

                                     else
                                        ""
                                    )
                            , Response.render (ActionData response)
                            )
            )


head : RouteBuilder.App Data ActionData RouteParams -> List Head.Tag
head app =
    []


form : Form.StyledHtmlForm String Bool Bool msg
form =
    Form.form
        (\darkMode ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap darkMode
            , view =
                \info ->
                    [ Html.button []
                        [ Html.text <|
                            if info.input then
                                "☀️ To Light Mode"

                            else
                                "️🌒 To Dark Mode"
                        ]
                    ]
            }
        )
        |> Form.hiddenField "darkMode"
            (Field.checkbox
                |> Field.withInitialValue not
            )


view :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> View.View (PagesMsg Msg)
view app shared =
    { title = "DarkMode"
    , body =
        [ Html.div
            [ css
                (if app.data.isDarkMode then
                    [ Css.color (Css.hex "aaa")
                    , Css.backgroundColor (Css.hex "000")
                    , Css.height (Css.vh 100)
                    ]

                 else
                    []
                )
            ]
            [ form
                |> Pages.Form.renderStyledHtml []
                    (Form.options "dark-mode"
                        |> Form.withInput app.data.isDarkMode
                        |> Pages.Form.withConcurrent
                    )
                    app
            , Html.text <|
                "Current mode: "
                    ++ (if app.data.isDarkMode then
                            "Dark Mode"

                        else
                            "Light Mode"
                       )
            ]
        ]
    }
