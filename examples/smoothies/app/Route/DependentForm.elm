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
    Request.formParserResultNew [ dependentParser ]
        |> Request.map
            (\parsedForm ->
                let
                    _ =
                        Debug.log "parsedForm"
                            (case parsedForm of
                                Ok (ParsedLink url) ->
                                    "Received a link: " ++ url

                                Ok (ParsedPost post) ->
                                    "Received a post: " ++ post.title ++ " , " ++ (post.body |> Maybe.withDefault "No body")

                                Err formErrors ->
                                    "formErrors"
                            )
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
        , Form.renderHtml app () dependentParser
        ]
    }


type PostAction
    = ParsedLink String
    | ParsedPost { title : String, body : Maybe String }


linkForm : Form.HtmlSubForm String PostAction data Msg
linkForm =
    Form.init
        (\url ->
            Form.ok (ParsedLink url.value)
        )
        (\formState url ->
            [ Html.h2 [] [ Html.text "Create a link" ]
            , fieldView formState "URL" url
            ]
        )
        |> Form.field "url"
            (Field.text
                |> Field.required "Required"
                |> Field.url
            )


postForm : Form.HtmlSubForm String PostAction data Msg
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
        (\formState title body ->
            [ Html.h2 [] [ Html.text "Create a post" ]
            , fieldView formState "Title" title
            , fieldView formState "Body" body
            ]
        )
        |> Form.field "title" (Field.text |> Field.required "Required")
        |> Form.field "body" Field.text


dependentParser : Form.HtmlForm String PostAction data Msg
dependentParser =
    Form.init
        (\kind postForm_ ->
            postForm_ kind.value
                |> Form.andThen identity
        )
        (\formState kind postForm_ ->
            let
                parsedKind : Maybe PostKind
                parsedKind =
                    -- TODO don't manually parse, this should be provided as a record field (`parsed : Maybe parsed`)
                    case kind.value of
                        Just "link" ->
                            Just Link

                        Just "post" ->
                            Just Post

                        _ ->
                            Nothing
            in
            ( []
            , [ Pages.FieldRenderer.radio []
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
                    (case parsedKind of
                        Just justKind ->
                            postForm_ justKind

                        Nothing ->
                            [ Html.text "Please select a post kind" ]
                    )
              , Html.button [] [ Html.text "Submit" ]
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


fieldView :
    Form.Context String
    -> String
    -> Form.ViewField Pages.FieldRenderer.Input
    -> Html msg
fieldView formState label field =
    let
        errors =
            formState.errors
                |> Dict.get field.name
                |> Maybe.withDefault []

        errorsView : Html msg
        errorsView =
            (if formState.submitAttempted || True then
                errors
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