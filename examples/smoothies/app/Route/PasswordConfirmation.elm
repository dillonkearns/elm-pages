module Route.PasswordConfirmation exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Dict
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Field as Field
import Pages.FieldRenderer
import Pages.Form as Form
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
    Request.formParserResultNew [ dependentParser ]
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
        , Form.renderHtml { method = Form.Post, submitStrategy = Form.TransitionStrategy } app () dependentParser
        ]
    }


type PostAction
    = ParsedLink String
    | ParsedPost { title : String, body : Maybe String }


confirmedPasswordForm : Form.HtmlSubForm String String data Msg
confirmedPasswordForm =
    Form.init
        (\password passwordConfirmation ->
            if password.value == passwordConfirmation.value then
                Form.ok password.value

            else
                Form.fail passwordConfirmation "Must match password"
        )
        (\formState password passwordConfirmation ->
            [ Html.h2 [] [ Html.text "Create a post" ]
            , fieldView formState "Password" password
            , fieldView formState "Password Confirmation" passwordConfirmation
            ]
        )
        |> Form.field "password" (Field.text |> Field.password |> Field.required "Required")
        |> Form.field "password-confirmation" (Field.text |> Field.password |> Field.required "Required")


dependentParser : Form.HtmlForm String String data Msg
dependentParser =
    Form.init
        (\username confirmedPassword ->
            confirmedPassword
                |> Form.andThen identity
        )
        (\formState username confirmedPassword ->
            ( []
            , [ Html.div [] confirmedPassword
              , fieldView formState "Username" username
              , Html.button [] [ Html.text "Submit" ]
              ]
            )
        )
        |> Form.field "username" (Field.text |> Field.required "Required")
        |> Form.subGroup confirmedPasswordForm


fieldView :
    Form.Context String data
    -> String
    -> Form.ViewField String parsed Pages.FieldRenderer.Input
    -> Html msg
fieldView formState label field =
    let
        errorsView : Html msg
        errorsView =
            (if formState.submitAttempted || True then
                formState.errors
                    |> Dict.get field.name
                    |> Maybe.withDefault []
                    |> List.map (\error -> Html.li [] [ Html.text error ])

             else
                []
            )
                |> Html.ul [ Attr.style "color" "red" ]
    in
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Pages.FieldRenderer.input []
            ]
        , errorsView
        ]


type PostKind
    = Link
    | Post
