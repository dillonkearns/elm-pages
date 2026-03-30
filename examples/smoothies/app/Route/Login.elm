module Route.Login exposing (ActionData, Data, Model, Msg, route)

import Data.User
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation exposing (Validation)
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import MySession
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Login =
    { username : String
    , password : String
    }


form : Pages.Form.FormWithServerValidations String String input (List (Html (PagesMsg Msg)))
form =
    Form.form
        (\username password ->
            { combine =
                Validation.succeed
                    (\u p ->
                        Data.User.login { username = u, expectedPasswordHash = p }
                            |> BackendTask.map
                                (\maybeUserId ->
                                    case maybeUserId of
                                        Just userId ->
                                            Validation.succeed userId

                                        Nothing ->
                                            Validation.fail "Username and password do not match" Validation.global
                                )
                    )
                    |> Validation.andMap username
                    |> Validation.andMap password
            , view =
                \info ->
                    [ username |> fieldView info "Username"
                    , password |> fieldView info "Password"
                    , globalErrors info
                    , Html.button []
                        [ if info.submitting then
                            Html.text "Logging in..."

                          else
                            Html.text "Login"
                        ]
                    ]
            }
        )
        |> Form.field "username" (Field.text |> Field.email |> Field.required "Required")
        |> Form.field "password" (Field.text |> Field.password |> Field.required "Required")


fieldView :
    Form.Context String data
    -> String
    -> Validation.Field String parsed Form.FieldView.Input
    -> Html msg
fieldView formState label field =
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Form.FieldView.inputStyled []
            ]
        , errorsForField formState field
        ]


errorsForField : Form.Context String data -> Validation.Field String parsed kind -> Html msg
errorsForField formState field =
    (if True || formState.submitAttempted then
        formState.errors
            |> Form.errorsForField field
            |> List.map (\error -> Html.li [] [ Html.text error ])

     else
        []
    )
        |> Html.ul [ Attr.style "color" "red" ]


globalErrors : Form.Context String data -> Html msg
globalErrors formState =
    formState.errors
        |> Form.errorsForField Validation.global
        |> List.map (\error -> Html.li [] [ Html.text error ])
        |> Html.ul [ Attr.style "color" "red" ]


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    request
        |> MySession.withSession
            (\session ->
                case session of
                    Ok okSession ->
                        ( okSession
                        , okSession
                            |> Session.get "userId"
                            |> Data
                            |> Server.Response.render
                        )
                            |> BackendTask.succeed

                    _ ->
                        ( Session.empty
                        , { username = Nothing }
                            |> Server.Response.render
                        )
                            |> BackendTask.succeed
            )


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    request
        |> MySession.withSession
            (\session ->
                case request |> Request.formDataWithServerValidation (form |> Form.Handler.init identity) of
                    Nothing ->
                        BackendTask.fail (FatalError.fromString "Invalid form response")

                    Just nameResultData ->
                        nameResultData
                            |> BackendTask.map
                                (\nameResult ->
                                    case nameResult of
                                        Err errors ->
                                            ( session
                                                |> Result.withDefault Session.empty
                                            , Server.Response.render
                                                { errors = errors
                                                }
                                            )

                                        Ok ( _, userId ) ->
                                            ( session
                                                |> Result.withDefault Session.empty
                                                |> Session.insert "userId" userId
                                            , Route.redirectTo Route.Index
                                            )
                                )
            )


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    []


type alias Data =
    { username : Maybe String
    }


type alias ActionData =
    { errors : Form.ServerResponse String
    }


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app sharedModel =
    { title = "Login"
    , body =
        [ Html.p []
            [ Html.text
                (case app.data.username of
                    Just username ->
                        "Hello! You are already logged in."

                    Nothing ->
                        "You aren't logged in yet."
                )
            ]
        , form
            |> Pages.Form.renderStyledHtml
                []
                (Form.options "login"
                    |> Form.withServerResponse (app.action |> Maybe.map .errors)
                )
                app
        , Html.p []
            [ Html.text "Don't have an account? "
            , Html.a [ Attr.href "/signup" ] [ Html.text "Sign up" ]
            ]
        ]
    }
