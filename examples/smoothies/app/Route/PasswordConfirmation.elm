module Route.PasswordConfirmation exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Dict
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Validation)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
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
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed (DataSource.succeed (Response.render Data))


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Request.formDataWithoutServerValidation2 [ dependentParser ]
        |> Request.map
            (\parsedForm ->
                let
                    _ =
                        Debug.log "parsedForm" parsedForm
                in
                DataSource.succeed
                    (Response.render ActionData)
            )


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Dependent Form Example"
    , body =
        [ Html.h2 [] [ Html.text "Example" ]
        , dependentParser
            |> Form.toDynamicTransitionNew "form"
            |> Form.renderHtml []
                -- TODO pass in form response from ActionData
                Nothing
                app
                ()
        ]
    }


type PostAction
    = ParsedLink String
    | ParsedPost { title : String, body : Maybe String }


type alias Validated =
    { username : String, password : String }


dependentParser : Form.HtmlFormNew String { username : String, password : String } data Msg
dependentParser =
    Form.init2
        (\username password passwordConfirmation ->
            { combine =
                username
                    |> Validation.map Validated
                    |> Validation.andMap
                        (Validation.map2
                            (\passwordValue passwordConfirmationValue ->
                                if passwordValue == passwordConfirmationValue then
                                    Validation.succeed passwordValue

                                else
                                    Validation.fail2 passwordConfirmation "Must match password"
                            )
                            password
                            passwordConfirmation
                            |> Validation.andThen identity
                        )
            , view =
                \formState ->
                    [ fieldView formState "Username" username
                    , fieldView formState "Password" password
                    , fieldView formState "Password Confirmation" passwordConfirmation
                    ]
            }
        )
        |> Form.field2 "username" (Field.text |> Field.required "Required")
        |> Form.field2 "password" (Field.text |> Field.password |> Field.required "Required")
        |> Form.field2 "password-confirmation" (Field.text |> Field.password |> Field.required "Required")


fieldView :
    Form.Context String data
    -> String
    -> Validation String parsed Form.FieldView.Input
    -> Html msg
fieldView formState label field =
    let
        errorsView : Html msg
        errorsView =
            (if formState.submitAttempted || True then
                formState.errors
                    |> Form.errorsForField2 field
                    |> List.map (\error -> Html.li [] [ Html.text error ])

             else
                []
            )
                |> Html.ul [ Attr.style "color" "red" ]
    in
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Form.FieldView.input2 []
            ]
        , errorsView
        ]


type PostKind
    = Link
    | Post
