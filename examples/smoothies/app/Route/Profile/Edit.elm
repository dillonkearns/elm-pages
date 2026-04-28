module Route.Profile.Edit exposing (ActionData, Data, Model, Msg, route)

import Data.User as User exposing (User)
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
    ( {}
    , Effect.none
    )


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
    { user : User
    }


type alias ActionData =
    Result { fields : List ( String, String ), errors : Dict String (List String) } Action


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    MySession.expectSessionDataOrRedirect (Session.get "userId")
        (\userId session ->
            User.find userId
                |> BackendTask.map
                    (\user ->
                        user
                            |> Data
                            |> Response.render
                            |> Tuple.pair session
                    )
        )
        request


type alias Action =
    { username : String
    , name : String
    }


formParser : Pages.Form.FormWithServerValidations String Action Data (List (Html (PagesMsg msg)))
formParser =
    Form.form
        (\username name ->
            { combine =
                Validation.succeed
                    (\u n ->
                        toValidUsername u username
                            |> BackendTask.map
                                (\vu ->
                                    Validation.succeed Action
                                        |> Validation.andMap vu
                                        |> Validation.andMap (Validation.succeed n)
                                )
                    )
                    |> Validation.andMap username
                    |> Validation.andMap name
            , view =
                \info ->
                    let
                        errorsView field =
                            (if True then
                                info.errors
                                    |> Form.errorsForField field
                                    |> List.map (\error -> Html.li [] [ Html.text error ])

                             else
                                []
                            )
                                |> Html.ul [ Attr.style "color" "red" ]
                    in
                    [ Html.div
                        []
                        [ Html.label [] [ Html.text "Username ", username |> FieldView.inputStyled [] ]
                        , errorsView username
                        ]
                    , Html.div []
                        [ Html.label [] [ Html.text "Name ", name |> FieldView.inputStyled [] ]
                        , errorsView name
                        ]
                    , Html.button []
                        [ Html.text <|
                            if info.submitting then
                                "Updating..."

                            else
                                "Update"
                        ]
                    ]
            }
        )
        |> Form.field "username"
            (Field.text
                |> Field.required "Username is required"
                |> Field.validateMap validateUsername
                |> Field.withInitialValue (\{ user } -> user.username)
            )
        |> Form.field "name"
            (Field.text
                |> Field.required "Name is required"
                |> Field.withInitialValue (\{ user } -> user.name)
            )


toValidUsername : String -> Validation.Field String parsed1 field -> BackendTask FatalError (Validation.Validation String String Never Never)
toValidUsername username usernameField =
    BackendTask.succeed
        (if username == "dillon123" then
            Validation.fail "This username is taken" usernameField

         else
            Validation.succeed username
        )


validateUsername : String -> Result String String
validateUsername rawUsername =
    if rawUsername |> String.contains "@" then
        Err "Cannot contain @"

    else
        Ok rawUsername


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    -- TODO: re-implement with file-based data layer
    -- Original: parsed form with server validation, called User.updateUser, redirected to Profile
    BackendTask.succeed (Response.render (Ok { username = "", name = "" }))


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "Ctrl-R Smoothies"
    , body =
        [ Html.p []
            [ Html.text <| "Welcome " ++ app.data.user.name ++ "!" ]
        , case app.action of
            Just (Err error) ->
                Html.text "Form errors"

            Nothing ->
                Html.text "No action"

            _ ->
                Html.text "No errors"
        , formParser
            |> Pages.Form.renderStyledHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                (Form.options "edit-form"
                    |> Form.withInput app.data
                )
                app
        ]
    }
