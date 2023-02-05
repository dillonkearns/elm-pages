module Route.Admin.Slug_ exposing (ActionData, Data, route, RouteParams, Msg, Model)

{-|

@docs ActionData, Data, route, RouteParams, Msg, Model

-}

import BackendTask
import BackendTask.Custom
import Date exposing (Date)
import Effect
import ErrorPage
import FatalError
import Form
import Form.Field
import Form.FieldView
import Form.Validation
import Form.Value
import Head
import Html
import Html.Attributes
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.Msg
import Pages.PageUrl
import Pages.Script
import Path
import Platform.Sub
import Post
import Route
import RouteBuilder
import Server.Request
import Server.Response
import Shared
import Time
import View


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { slug : String }


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
    { post : Post
    }


type alias ActionData =
    { errors : Form.Response String }


type alias Post =
    { title : String
    , body : String
    , slug : String
    , publish : Maybe Date
    }


data :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed
        (if routeParams.slug == "new" then
            Server.Response.render
                { post =
                    { slug = ""
                    , title = ""
                    , body = ""
                    , publish = Nothing
                    }
                }
                |> BackendTask.succeed

         else
            BackendTask.Custom.run "getPost"
                (Encode.string routeParams.slug)
                (Decode.nullable Post.decoder)
                |> BackendTask.allowFatal
                |> BackendTask.map
                    (\maybePost ->
                        case maybePost of
                            Just post ->
                                Server.Response.render
                                    { post = post
                                    }

                            Nothing ->
                                Server.Response.errorPage ErrorPage.NotFound
                    )
        )


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
    { title = "Posts.Slug_.Edit"
    , body =
        [ Html.h2 [] [ Html.text "Form" ]
        , Form.renderHtml
            []
            (\renderStyledHtmlUnpack -> Just renderStyledHtmlUnpack.errors)
            app
            app.data.post
            (Form.toDynamicTransition "form" form)
        ]
    }


action :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.map
        (\( formResponse, parsedForm ) ->
            case parsedForm of
                Ok okForm ->
                    let
                        createPost : Bool
                        createPost =
                            okForm.slug == "new"
                    in
                    BackendTask.Custom.run
                        (if createPost then
                            "createPost"

                         else
                            "updatePost"
                        )
                        (Encode.object
                            [ ( "slug", Encode.string okForm.slug )
                            , ( "title", Encode.string okForm.title )
                            , ( "body", Encode.string okForm.body )
                            , ( "publish"
                              , okForm.publish
                                    |> Maybe.map (Date.toIsoString >> Encode.string)
                                    |> Maybe.withDefault Encode.null
                              )
                            ]
                        )
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTask.map
                            (\() ->
                                Route.redirectTo
                                    (Route.Admin__Slug_ { slug = okForm.slug })
                            )

                Err invalidForm ->
                    BackendTask.succeed
                        (Server.Response.render
                            { errors = formResponse }
                        )
        )
        (Server.Request.formData (Form.initCombined Basics.identity form))


form : Form.DoneForm String ParsedForm Post (List (Html.Html (Pages.Msg.Msg Msg)))
form =
    (\title slug body publish ->
        { combine =
            ParsedForm
                |> Form.Validation.succeed
                |> Form.Validation.andMap title
                |> Form.Validation.andMap slug
                |> Form.Validation.andMap body
                |> Form.Validation.andMap publish
        , view =
            \formState ->
                let
                    fieldView label field =
                        Html.div []
                            [ Html.label []
                                [ Html.text (label ++ " ")
                                , Form.FieldView.input [] field
                                , errorsView formState.errors field
                                ]
                            ]
                in
                [ fieldView "title" title
                , fieldView "slug" slug
                , fieldView "body" body
                , fieldView "publish" publish
                , if formState.isTransitioning then
                    Html.button
                        [ Html.Attributes.disabled True
                        , Html.Attributes.attribute "aria-busy" "true"
                        ]
                        [ Html.text "Submitting..." ]

                  else
                    Html.button []
                        [ Html.text "Submit" ]
                ]
        }
    )
        |> Form.init
        |> Form.field "title"
            (Form.Field.required "Required" Form.Field.text
                |> Form.Field.withInitialValue (.title >> Form.Value.string)
            )
        |> Form.field "slug"
            (Form.Field.required "Required" Form.Field.text
                |> Form.Field.withInitialValue (.slug >> Form.Value.string)
            )
        |> Form.field "body"
            (Form.Field.required "Required" Form.Field.text
                |> Form.Field.textarea { rows = Just 10, cols = Just 80 }
                |> Form.Field.withInitialValue (.body >> Form.Value.string)
            )
        |> Form.field "publish"
            (Form.Field.date { invalid = \dateUnpack -> "" }
                |> Form.Field.withOptionalInitialValue
                    (.publish >> Maybe.map Form.Value.date)
            )


type alias ParsedForm =
    { title : String, slug : String, body : String, publish : Maybe Date }


errorsView :
    Form.Errors String
    -> Form.Validation.Field String parsed kind
    -> Html.Html (Pages.Msg.Msg Msg)
errorsView errors field =
    if List.isEmpty (Form.errorsForField field errors) then
        Html.div [] []

    else
        Html.div
            []
            [ Html.ul
                []
                (List.map
                    (\error ->
                        Html.li
                            [ Html.Attributes.style "color" "red" ]
                            [ Html.text error ]
                    )
                    (Form.errorsForField field errors)
                )
            ]
