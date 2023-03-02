module Route.DependentForm exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Combined, Field)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
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
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
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


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.succeed (BackendTask.succeed (Response.render Data))


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    Request.formData (dependentParser |> Form.initCombined identity)
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
                BackendTask.succeed
                    (Response.render ActionData)
            )


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model app =
    { title = "Dependent Form Example"
    , body =
        [ Html.h2 [] [ Html.text "Example" ]
        , dependentParser
            |> Form.toDynamicTransition "dependent-example"
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


type alias PostInfo =
    { title : String, body : Maybe String }


linkForm : Form.HtmlForm String PostAction data Msg
linkForm =
    Form.init
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


postForm : Form.HtmlForm String PostAction data Msg
postForm =
    Form.init
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


dependentParser : Form.HtmlForm String PostAction data Msg
dependentParser =
    Form.init
        (\kind postForm_ ->
            { combine =
                kind
                    |> Validation.andThen postForm_.combine
            , view =
                \formState ->
                    [ Form.FieldView.radio []
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
    -> Field String parsed Form.FieldView.Input
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
            , field |> Form.FieldView.input []
            ]
        , errorsView
        ]


type PostKind
    = Link
    | Post
