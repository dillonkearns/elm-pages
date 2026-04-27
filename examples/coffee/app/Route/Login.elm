module Route.Login exposing (ActionData, Data, Model, Msg, route)

{-| Sign in. Hashes the password with the `hashPassword` custom port,
looks up the user in Hasura, and either sets the `userId` cookie or
returns a server-validation error.
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


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { username : Maybe String }


type alias ActionData =
    { errors : Form.ServerResponse String }


loginForm : Pages.Form.FormWithServerValidations String String input (List (Html (PagesMsg Msg)))
loginForm =
    Form.form
        (\username password ->
            { combine =
                Validation.succeed
                    (\u p ->
                        BackendTask.Custom.run "hashPassword"
                            (Json.Encode.string p)
                            Json.Decode.string
                            |> BackendTask.allowFatal
                            |> BackendTask.andThen
                                (\hashed ->
                                    User.login { username = u, expectedPasswordHash = hashed }
                                        |> BackendTask.map
                                            (\maybeUserId ->
                                                case maybeUserId of
                                                    Just userId ->
                                                        Validation.succeed userId

                                                    Nothing ->
                                                        Validation.fail "Username and password do not match" Validation.global
                                            )
                                )
                    )
                    |> Validation.andMap username
                    |> Validation.andMap password
            , view =
                \info ->
                    [ Html.div [ Attr.class "bh-eyebrow" ] [ Html.text "Members · Sign in" ]
                    , Html.h1 [] [ Html.text "Welcome", Html.br [] [], Html.text "back." ]
                    , Html.p [ Attr.class "sub" ]
                        [ Html.text "Pick up where you left off — your bag, saved drinks, and standing orders are waiting." ]
                    , globalErrorBanner info
                    , bhField info "Email" username
                    , bhField info "Password" password
                    , Html.button [ Attr.class "bh-submit", Attr.attribute "data-loading" (boolAttr info.submitting) ]
                        [ if info.submitting then
                            Html.text "Signing in"

                          else
                            Html.text "Sign in"
                        ]
                    , Html.div [ Attr.class "bh-login-foot" ]
                        [ Html.text "No account yet? "
                        , Html.a [ Attr.href "/signup" ] [ Html.text "Become a member" ]
                        ]
                    ]
            }
        )
        |> Form.field "username" (Field.text |> Field.email |> Field.required "Required")
        |> Form.field "password" (Field.text |> Field.password |> Field.required "Required")


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


globalErrorBanner : Form.Context String data -> Html msg
globalErrorBanner info =
    case info.errors |> Form.errorsForField Validation.global |> List.head of
        Just msg ->
            Html.div [ Attr.class "bh-server-banner" ]
                [ Html.div []
                    [ Html.div [ Attr.class "bh-mono" ] [ Html.text "server validation" ]
                    , Html.div [ Attr.style "margin-top" "2px" ] [ Html.text msg ]
                    ]
                ]

        Nothing ->
            Html.text ""


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data _ request =
    request
        |> MySession.withSession
            (\session ->
                case session of
                    Ok ok ->
                        BackendTask.succeed
                            ( ok
                            , ok |> Session.get "userId" |> Data |> Response.render
                            )

                    _ ->
                        BackendTask.succeed
                            ( Session.empty
                            , Response.render { username = Nothing }
                            )
            )


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action _ request =
    request
        |> MySession.withSession
            (\session ->
                case request |> Request.formDataWithServerValidation (loginForm |> Form.Handler.init identity) of
                    Nothing ->
                        BackendTask.fail (FatalError.fromString "Invalid form response")

                    Just nameResult ->
                        nameResult
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
    { title = "Sign in · Blendhaus"
    , body =
        [ View.Coffee.loginPage
            { aside = View.Coffee.loginAside
            , form =
                loginForm
                    |> Pages.Form.renderHtml
                        [ Attr.class "bh-login-form" ]
                        (Form.options "login"
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
