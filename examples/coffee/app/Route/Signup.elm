module Route.Signup exposing (ActionData, Data, Model, Msg, route)

{-| Become a member. Hashes the password, inserts a row in `users`,
sets the session cookie, redirects to the menu.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Data.CoffeeUser as User
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation exposing (Validation)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode
import Json.Encode
import MySession
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)
import View.Coffee


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    {}


type alias ActionData =
    { errors : Form.ServerResponse String }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


signupForm : Pages.Form.FormWithServerValidations String String input (List (Html (PagesMsg Msg)))
signupForm =
    Form.form
        (\name username password ->
            { combine =
                Validation.succeed
                    (\n u p ->
                        BackendTask.Custom.run "hashPassword"
                            (Json.Encode.string p)
                            Json.Decode.string
                            |> BackendTask.allowFatal
                            |> BackendTask.andThen
                                (\hashed ->
                                    User.signup { name = n, username = u, passwordHash = hashed }
                                        |> BackendTask.map
                                            (\maybeUserId ->
                                                case maybeUserId of
                                                    Just userId ->
                                                        Validation.succeed userId

                                                    Nothing ->
                                                        Validation.fail "Could not create that account" Validation.global
                                            )
                                )
                    )
                    |> Validation.andMap name
                    |> Validation.andMap username
                    |> Validation.andMap password
            , view =
                \info ->
                    [ Html.div [ Attr.class "bh-eyebrow" ] [ Html.text "Become a member" ]
                    , Html.h1 [] [ Html.text "Create an account." ]
                    , Html.p [ Attr.class "sub" ]
                        [ Html.text "Save your standing order, skip the line, and pick up where you left off." ]
                    , bhField info "Name" name
                    , bhField info "Email" username
                    , bhField info "Password" password
                    , Html.button [ Attr.class "bh-submit", Attr.attribute "data-loading" (boolAttr info.submitting) ]
                        [ if info.submitting then
                            Html.text "Signing up"

                          else
                            Html.text "Sign Up"
                        ]
                    , Html.div [ Attr.class "bh-login-foot" ]
                        [ Html.text "Already a member? "
                        , Html.a [ Attr.href "/login" ] [ Html.text "Sign in" ]
                        ]
                    ]
            }
        )
        |> Form.field "name" (Field.text |> Field.required "Required")
        |> Form.field "username" (Field.text |> Field.email |> Field.required "Required")
        |> Form.field "password"
            (Field.text
                |> Field.password
                |> Field.required "Required"
                |> Field.withMinLength 6 "Password must be at least 6 characters"
            )


bhField :
    Form.Context String data
    -> String
    -> Validation.Field String parsed Form.FieldView.Input
    -> Html msg
bhField info label field =
    let
        fieldErrors =
            Form.errorsForField field info.errors
    in
    Html.div
        [ Attr.class "bh-field"
        , Attr.attribute "data-error" (boolAttr (not (List.isEmpty fieldErrors)))
        ]
        [ Html.label [] [ Html.text label ]
        , field |> Form.FieldView.input []
        , case fieldErrors of
            [] ->
                Html.text ""

            err :: _ ->
                Html.div [ Attr.class "err" ] [ Html.text err ]
        ]


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data _ _ =
    BackendTask.succeed (Response.render {})


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action _ request =
    request
        |> MySession.withSession
            (\session ->
                case request |> Request.formDataWithServerValidation (signupForm |> Form.Handler.init identity) of
                    Nothing ->
                        BackendTask.fail (FatalError.fromString "Invalid form response")

                    Just userResult ->
                        userResult
                            |> BackendTask.map
                                (\result ->
                                    case result of
                                        Err errors ->
                                            ( session |> Result.withDefault Session.empty
                                            , Response.render { errors = errors }
                                            )

                                        Ok ( _, userId ) ->
                                            ( session
                                                |> Result.withDefault Session.empty
                                                |> Session.insert "userId" userId
                                            , Route.redirectTo Route.Index
                                            )
                                )
            )


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


view : App Data ActionData RouteParams -> Shared.Model -> View (PagesMsg Msg)
view app _ =
    { title = "Become a member · Blendhaus"
    , body =
        [ View.Coffee.loginPage
            { aside = View.Coffee.signupAside
            , form =
                signupForm
                    |> Pages.Form.renderHtml
                        [ Attr.class "bh-login-form" ]
                        (Form.options "signup"
                            |> Form.withServerResponse (app.action |> Maybe.map .errors)
                        )
                        app
            }
        ]
    }


boolAttr : Bool -> String
boolAttr b =
    if b then
        "true"

    else
        "false"
