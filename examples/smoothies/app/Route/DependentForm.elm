module Route.DependentForm exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
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
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
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
    ( {}, Effect.none )


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
    {}


type alias ActionData =
    {}


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.succeed (Response.render Data)


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    case request |> Request.formData (dependentParser |> Form.Handler.init identity) of
        Just ( _, parsedForm ) ->
            BackendTask.succeed (Response.render ActionData)

        Nothing ->
            BackendTask.succeed (Response.render ActionData)


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
    { title = "Dependent Form Example"
    , body =
        [ Html.h2 [] [ Html.text "Example" ]
        , dependentParser
            |> Pages.Form.renderStyledHtml []
                (Form.options "dependent-example")
                app
        ]
    }


type PostAction
    = ParsedLink String
    | ParsedPost { title : String, body : Maybe String }


type alias PostInfo =
    { title : String, body : Maybe String }


linkForm : Form.StyledHtmlForm String PostAction data msg
linkForm =
    Form.form
        (\url ->
            { combine =
                Validation.succeed ParsedLink
                    |> Validation.andMap url
            , view =
                \formState ->
                    [ Html.h2 [] [ Html.text "Create a link" ]
                    , fieldView formState "URL" url
                    ]
            }
        )
        |> Form.field "url"
            (Field.text
                |> Field.required "Required"
                |> Field.url
            )


postForm : Form.StyledHtmlForm String PostAction data msg
postForm =
    Form.form
        (\title body ->
            { combine =
                Validation.succeed PostInfo
                    |> Validation.andMap title
                    |> Validation.andMap body
                    |> Validation.map ParsedPost
            , view =
                \formState ->
                    [ Html.h2 [] [ Html.text "Create a post" ]
                    , fieldView formState "Title" title
                    , fieldView formState "Body" body
                    ]
            }
        )
        |> Form.field "title" (Field.text |> Field.required "Required")
        |> Form.field "body" Field.text


dependentParser : Form.StyledHtmlForm String PostAction data msg
dependentParser =
    Form.form
        (\kind postForm_ ->
            { combine =
                kind
                    |> Validation.andThen postForm_.combine
            , view =
                \formState ->
                    [ Form.FieldView.radioStyled []
                        (\enum toRadio ->
                            Html.label []
                                [ toRadio []
                                , Html.text
                                    (case enum of
                                        Link ->
                                            "Link"

                                        Post ->
                                            "Post"
                                    )
                                ]
                        )
                        kind
                    , Html.div []
                        (case kind |> Validation.value of
                            Just justKind ->
                                postForm_.view justKind formState

                            Nothing ->
                                [ Html.text "Please select a post kind" ]
                        )
                    , Html.button [] [ Html.text "Submit" ]
                    ]
            }
        )
        |> Form.field "kind"
            (Field.select
                [ ( "link", Link )
                , ( "post", Post )
                ]
                (\_ -> "Invalid")
                |> Field.required "Required"
            )
        |> Form.dynamic
            (\parsedKind ->
                case parsedKind of
                    Link ->
                        linkForm

                    Post ->
                        postForm
            )


fieldView :
    Form.Context String data
    -> String
    -> Validation.Field String parsed Form.FieldView.Input
    -> Html msg
fieldView formState label field =
    let
        errorsView : Html msg
        errorsView =
            (if formState.submitAttempted || True then
                formState.errors
                    |> Form.errorsForField field
                    |> List.map (\error -> Html.li [] [ Html.text error ])

             else
                []
            )
                |> Html.ul [ Attr.style "color" "red" ]
    in
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Form.FieldView.inputStyled []
            ]
        , errorsView
        ]


type PostKind
    = Link
    | Post
