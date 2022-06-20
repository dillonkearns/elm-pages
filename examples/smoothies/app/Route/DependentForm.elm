module Route.DependentForm exposing (ActionData, Data, Model, Msg, route)

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
    Request.skip "No action."


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
        , Form.renderHtml app () dependentParser
        ]
    }


type PostAction
    = ParsedLink String
    | ParsedPost { title : String, body : Maybe String }


linkForm : Form.HtmlForm String PostAction data Msg
linkForm =
    Form.init
        (\url ->
            Form.ok (ParsedLink url.value)
        )
        (\fieldErrors url -> ( [], [] ))
        |> Form.field "url"
            (Field.text
                |> Field.required "Required"
                |> Field.url
            )


postForm : Form.HtmlForm String PostAction data Msg
postForm =
    Form.init
        (\title body ->
            Form.ok
                (ParsedPost
                    { title = title.value
                    , body = body.value
                    }
                )
        )
        (\fieldErrors title body -> ( [], [] ))
        |> Form.field "title" (Field.text |> Field.required "Required")
        |> Form.field "body" Field.text


dependentParser : Form.HtmlForm String PostAction data Msg
dependentParser =
    Form.init
        (\kind postForm_ ->
            postForm_ kind.value
        )
        (\formState kind postForm_ ->
            let
                something =
                    -- TODO do I need to have `Maybe parsed` available in view fields?
                    postForm_ Nothing

                errors field =
                    formState.errors
                        |> Dict.get field.name
                        |> Maybe.withDefault []

                errorsView field =
                    (if formState.submitAttempted || True then
                        field
                            |> errors
                            |> List.map (\error -> Html.li [] [ Html.text error ])

                     else
                        []
                    )
                        |> Html.ul [ Attr.style "color" "red" ]

                fieldView label field =
                    Html.div []
                        [ Html.label []
                            [ Html.text (label ++ " ")
                            , field |> Pages.FieldRenderer.input []
                            ]
                        , errorsView field
                        ]
            in
            ( []
            , [--postForm_ Nothing
              ]
            )
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


type PostKind
    = Link
    | Post
