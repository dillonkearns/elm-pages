module Route.Signup exposing (ActionData, Data, Model, Msg, route)

import Data.User
import BackendTask exposing (BackendTask)
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
import Server.Response
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


form : Pages.Form.FormWithServerValidations String String input (List (Html (PagesMsg Msg)))
form =
    Form.form
        (\name username password ->
            { combine =
                Validation.succeed
                    (\n u p ->
                        Data.User.signup { name = n, username = u, password = p }
                            |> BackendTask.map
                                (\maybeUserId ->
                                    case maybeUserId of
                                        Just userId ->
                                            Validation.succeed userId

                                        Nothing ->
                                            Validation.fail "Could not create account." Validation.global
                                )
                    )
                    |> Validation.andMap name
                    |> Validation.andMap username
                    |> Validation.andMap password
            , view =
                \info ->
                    [ name |> fieldView info "Name"
                    , username |> fieldView info "Email"
                    , password |> fieldView info "Password"
                    , globalErrors info
                    , Html.button []
                        [ if info.submitting then
                            Html.text "Creating account..."

                          else
                            Html.text "Sign Up"
                        ]
                    ]
            }
        )
        |> Form.field "name" (Field.text |> Field.required "Required")
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
    (if formState.submitAttempted then
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


type alias Data =
    {}


type alias ActionData =
    { errors : Form.ServerResponse String
    }


data : RouteParams -> Request -> BackendTask FatalError (Server.Response.Response Data ErrorPage)
data _ _ =
    BackendTask.succeed (Server.Response.render {})


action : RouteParams -> Request -> BackendTask FatalError (Server.Response.Response ActionData ErrorPage)
action _ request =
    request
        |> MySession.withSession
            (\session ->
                case request |> Request.formDataWithServerValidation (form |> Form.Handler.init identity) of
                    Nothing ->
                        BackendTask.fail (FatalError.fromString "Invalid form response")

                    Just resultData ->
                        resultData
                            |> BackendTask.map
                                (\result ->
                                    case result of
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
head _ =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app _ =
    { title = "Sign Up"
    , body =
        [ Html.h2 [] [ Html.text "Create an account" ]
        , form
            |> Pages.Form.renderStyledHtml
                []
                (Form.options "signup"
                    |> Form.withServerResponse (app.action |> Maybe.map .errors)
                )
                app
        , Html.p []
            [ Html.text "Already have an account? "
            , Html.a [ Attr.href "/login" ] [ Html.text "Log in" ]
            ]
        ]
    }
