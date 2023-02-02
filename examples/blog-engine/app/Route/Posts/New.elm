module Route.Posts.New exposing (ActionData, Data, route, RouteParams, Msg, Model)

{-|

@docs ActionData, Data, route, RouteParams, Msg, Model

-}

import BackendTask
import Date
import Debug
import Effect
import ErrorPage
import FatalError
import Form
import Form.Field
import Form.FieldView
import Form.Validation
import Head
import Html
import Html.Attributes
import Pages.Msg
import Pages.PageUrl
import Pages.Script
import Path
import Platform.Sub
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
    { errors : Form.Response String }


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
        [ Html.h2 [] [ Html.text "Form" ]
        , Form.renderHtml
            []
            (\renderStyledHtmlUnpack -> Just renderStyledHtmlUnpack.errors)
            app
            ()
            (Form.toDynamicTransition "form" form)
        ]
    }


action :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.map
        (\formData ->
            case formData of
                ( formResponse, parsedForm ) ->
                    BackendTask.map
                        (\_ ->
                            Server.Response.render
                                { errors = formResponse }
                        )
                        (Pages.Script.log
                            (Debug.toString parsedForm)
                        )
        )
        (Server.Request.formData (Form.initCombined Basics.identity form))


form : Form.DoneForm String ParsedForm () (List (Html.Html (Pages.Msg.Msg Msg)))
form =
    Form.field
        "publish"
        (Form.Field.required
            "Required"
            (Form.Field.date { invalid = \_ -> "" })
        )
        ((\title slug markdown publish ->
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
                    |> Form.Validation.andMap markdown
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
                    , fieldView "markdown" markdown
                    , fieldView "publish" publish
                    , Html.button [] [ Html.text "Submit" ]
                    ]
            }
         )
            |> Form.init
            |> Form.field "title" (Form.Field.required "Required" Form.Field.text)
            |> Form.field "slug" (Form.Field.required "Required" Form.Field.text)
            |> Form.field "markdown" (Form.Field.required "Required" Form.Field.text |> Form.Field.textarea)
        )


type alias ParsedForm =
    { title : String, slug : String, markdown : String, publish : Date.Date }


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
                            [ Html.Attributes.style "color" "red" ]
                            [ Html.text error ]
                    )
                    (Form.errorsForField field errors)
                )
            ]
