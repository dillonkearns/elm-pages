module Route.Posts.New exposing (ActionData, Data, route, RouteParams, Msg, Model)

{-|

@docs ActionData, Data, route, RouteParams, Msg, Model

-}

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Date exposing (Date)
import Dict
import Effect
import ErrorPage
import FatalError
import Form
import Form.Field
import Form.FieldView
import Form.Validation
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import Markdown.Parser
import Markdown.Renderer
import Pages.Msg
import Pages.PageUrl
import Path
import Platform.Sub
import Route
import RouteBuilder
import Server.Request
import Server.Response
import Shared
import View


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.buildWithLocalState
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
        (RouteBuilder.serverRender { data = data, action = action, head = head })


init :
    Maybe Pages.PageUrl.PageUrl
    -> Shared.Model
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> ( Model, Effect.Effect Msg )
init pageUrl sharedModel app =
    ( {}, Effect.none )


update :
    Pages.PageUrl.PageUrl
    -> Shared.Model
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect.Effect msg )
update pageUrl sharedModel app msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions :
    Maybe Pages.PageUrl.PageUrl
    -> RouteParams
    -> Path.Path
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Platform.Sub.none


type alias Data =
    {}


type alias ActionData =
    { errors : Form.Response String
    , errorMessage : Maybe String
    }


data :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed (BackendTask.succeed (Server.Response.render {}))


head : RouteBuilder.StaticPayload Data ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    Maybe Pages.PageUrl.PageUrl
    -> Shared.Model
    -> Model
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> View.View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Posts.New"
    , body =
        [ Html.div
            [ Attr.style "display" "flex"
            , Attr.style "flex" "row"
            , Attr.class "hmmm"
            ]
            [ Html.div []
                [ Html.h2
                    []
                    [ Html.text "Form" ]
                , app.action
                    |> Maybe.andThen .errorMessage
                    |> Maybe.map
                        (\errorMessage ->
                            Html.p [ Attr.style "color" "red" ] [ Html.text errorMessage ]
                        )
                    |> Maybe.withDefault (Html.text "")
                , Form.renderHtml
                    []
                    (\renderStyledHtmlUnpack -> Just renderStyledHtmlUnpack.errors)
                    app
                    ()
                    (Form.toDynamicTransition "form" form)
                ]
            , postPreview app
            ]
        ]
    }


postPreview app =
    Html.div []
        [ Html.h1 []
            [ app.pageFormState
                |> Dict.get "form"
                |> Maybe.andThen (.fields >> Dict.get "title")
                |> Maybe.map .value
                |> Maybe.withDefault ""
                |> Html.text
            ]
        , app.pageFormState
            |> Dict.get "form"
            |> Maybe.andThen (.fields >> Dict.get "body")
            |> Maybe.map .value
            |> Maybe.withDefault ""
            |> renderMarkdown
        ]


renderMarkdown : String -> Html msg
renderMarkdown markdown =
    markdown
        |> Markdown.Parser.parse
        |> Result.withDefault []
        |> Markdown.Renderer.render Markdown.Renderer.defaultHtmlRenderer
        |> Result.withDefault []
        |> Html.div []


action :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.map
        (\formData ->
            case formData of
                ( formResponse, parsedForm ) ->
                    case parsedForm of
                        Ok okForm ->
                            BackendTask.Custom.run "createPost"
                                (Encode.object
                                    [ ( "slug", Encode.string okForm.slug )
                                    , ( "title", Encode.string okForm.title )
                                    , ( "body", Encode.string okForm.body )
                                    ]
                                )
                                (Decode.oneOf
                                    [ Decode.field "errorMessage" (Decode.string |> Decode.map Err)
                                    , Decode.succeed (Ok ())
                                    ]
                                )
                                |> BackendTask.allowFatal
                                |> BackendTask.map
                                    (\result ->
                                        case result of
                                            Ok () ->
                                                Route.redirectTo Route.Index

                                            Err errorMessage ->
                                                Server.Response.render { errors = formResponse, errorMessage = Just errorMessage }
                                    )

                        Err errors ->
                            Server.Response.render { errors = formResponse, errorMessage = Nothing }
                                |> BackendTask.succeed
        )
        (Server.Request.formData (Form.initCombined Basics.identity form))


form : Form.DoneForm String ParsedForm () (List (Html.Html (Pages.Msg.Msg Msg)))
form =
    Form.field
        "publish"
        (Form.Field.date { invalid = \_ -> "" })
        ((\title slug body publish ->
            { combine =
                ParsedForm
                    |> Form.Validation.succeed
                    |> Form.Validation.andMap title
                    |> Form.Validation.andMap
                        (slug
                            |> Form.Validation.andThen
                                (\slugValue ->
                                    if slugValue |> String.contains " " then
                                        Form.Validation.withError slug
                                            "Cannot contain spaces"
                                            (Form.Validation.mapWithNever identity slug)

                                    else
                                        Form.Validation.mapWithNever identity slug
                                )
                        )
                    |> Form.Validation.andMap body
                    |> Form.Validation.andMap publish
            , view =
                \formState ->
                    let
                        fieldView label field =
                            Html.div
                                []
                                [ Html.label
                                    []
                                    [ Html.text (label ++ " ")
                                    , Form.FieldView.input [] field
                                    , errorsView
                                        formState.errors
                                        field
                                    ]
                                ]
                    in
                    [ fieldView "title" title
                    , fieldView "slug" slug
                    , fieldView "body" body
                    , fieldView "publish" publish
                    , if formState.isTransitioning then
                        Html.button [ Attr.disabled True ]
                            [ Html.text "Submitting..."
                            ]

                      else
                        Html.button []
                            [ Html.text "Submit"
                            ]
                    ]
            }
         )
            |> Form.init
            |> Form.field "title" (Form.Field.required "Required" Form.Field.text)
            |> Form.field "slug" (Form.Field.required "Required" Form.Field.text)
            |> Form.field "body"
                (Form.Field.required "Required" Form.Field.text
                    |> Form.Field.textarea
                        { rows = Just 30, cols = Just 80 }
                )
        )


type alias ParsedForm =
    { title : String
    , slug : String
    , body : String
    , publish : Maybe Date
    }


errorsView :
    Form.Errors String
    -> Form.Validation.Field String parsed kind
    -> Html.Html (Pages.Msg.Msg Msg)
errorsView errors field =
    if List.isEmpty (Form.errorsForField field errors) then
        Html.div [] []

    else
        Html.div []
            [ Html.ul []
                (List.map
                    (\error ->
                        Html.li
                            [ Attr.style "color" "red" ]
                            [ Html.text error ]
                    )
                    (Form.errorsForField field errors)
                )
            ]
