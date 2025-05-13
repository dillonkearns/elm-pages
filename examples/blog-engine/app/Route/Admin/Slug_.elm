module Route.Admin.Slug_ exposing (ActionData, Data, route, RouteParams, Msg, Model)

{-|

@docs ActionData, Data, route, RouteParams, Msg, Model

-}

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Date exposing (Date)
import Effect
import Elm exposing (expose)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form exposing (Validated(..))
import Form.Field
import Form.FieldView
import Form.Handler
import Form.Validation
import Head
import Html exposing (Html)
import Html.Attributes
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import PageServerResponse exposing (PageServerResponse)
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Platform.Sub
import Post exposing (Post)
import Route
import RouteBuilder
import Server.Request exposing (Request)
import Server.Response
import Shared
import UrlPath
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
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect.Effect Msg )
init app shared =
    ( {}, Effect.none )


update :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect.Effect msg )
update app shared msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions :
    RouteParams
    -> UrlPath.UrlPath
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions routeParams path shared model =
    Sub.none


type alias Data =
    { post : Post
    }


type alias ActionData =
    { errors : Form.ServerResponse String }


data :
    RouteParams
    -> Request
    -> BackendTask FatalError (PageServerResponse Data ErrorPage)
data routeParams request =
    if routeParams.slug == "new" then
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


head : RouteBuilder.App Data ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View.View (PagesMsg Msg)
view app shared model =
    { title =
        if app.routeParams.slug == "new" then
            "Create Post"

        else
            "Edit Post"
    , body =
        [ Html.h2 [] [ Html.text "Form" ]
        , form
            |> Pages.Form.renderHtml []
                (Form.options "form"
                    |> Form.withInput app.data.post
                    |> Form.withServerResponse
                        (app.action |> Maybe.map .errors)
                )
                app
        , if app.routeParams.slug == "new" then
            Html.text ""

          else
            deleteForm
                |> Pages.Form.renderHtml []
                    (Form.options "delete")
                    app
        ]
    }


action :
    RouteParams
    -> Request
    -> BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage)
action routeParams request =
    case Server.Request.formData formHandlers request of
        Just ( formResponse, parsedForm ) ->
            case parsedForm of
                Valid Delete ->
                    BackendTask.Custom.run "deletePost"
                        (Encode.object
                            [ ( "slug", Encode.string routeParams.slug )
                            ]
                        )
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTask.map
                            (\() ->
                                Route.redirectTo Route.Index
                            )

                Valid (CreateOrEdit okForm) ->
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

                Invalid _ invalidForm ->
                    BackendTask.succeed
                        (Server.Response.render
                            { errors = formResponse }
                        )

        Nothing ->
            BackendTask.fail (FatalError.fromString "Invalid form response")


form : Form.HtmlForm String Post Post msg
form =
    (\title slug body publish ->
        { combine =
            Post
                |> Form.Validation.succeed
                |> Form.Validation.andMap title
                |> Form.Validation.andMap body
                |> Form.Validation.andMap slug
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
                , buttonWithTransition [] "Submit" "Submitting..." formState
                ]
        }
    )
        |> Form.form
        |> Form.hiddenKind ( "kind", "create-or-edit" ) "Expected create-or-edit"
        |> Form.field "title"
            (Form.Field.required "Required" Form.Field.text
                |> Form.Field.withInitialValue .title
            )
        |> Form.field "slug"
            (Form.Field.required "Required" Form.Field.text
                |> Form.Field.withInitialValue .slug
            )
        |> Form.field "body"
            (Form.Field.required "Required" Form.Field.text
                |> Form.Field.textarea { rows = Just 10, cols = Just 80 }
                |> Form.Field.withInitialValue .body
            )
        |> Form.field "publish"
            (Form.Field.date { invalid = \_ -> "Invalid date." }
                |> Form.Field.withOptionalInitialValue .publish
            )


type Action
    = Delete
    | CreateOrEdit Post


formHandlers : Form.Handler.Handler String Action
formHandlers =
    deleteForm
        |> Form.Handler.init (\() -> Delete)
        |> Form.Handler.with CreateOrEdit form


deleteForm : Form.HtmlForm String () input msg
deleteForm =
    Form.form
        { combine = Form.Validation.succeed ()
        , view =
            \formState ->
                [ buttonWithTransition
                    [ Html.Attributes.style "background-color" "red"
                    , Html.Attributes.style "border" "red"
                    ]
                    "Delete"
                    "Deleting..."
                    formState
                ]
        }
        |> Form.hiddenKind ( "kind", "delete" ) "Expected delete"


buttonWithTransition : List (Html.Attribute msg) -> String -> String -> { a | submitting : Bool } -> Html msg
buttonWithTransition attributes initialText transitioningText formState =
    if formState.submitting then
        Html.button
            (attributes
                ++ [ Html.Attributes.disabled True
                   , Html.Attributes.attribute "aria-busy" "true"
                   ]
            )
            [ Html.text transitioningText ]

    else
        Html.button
            (attributes ++ [])
            [ Html.text initialText ]


errorsView :
    Form.Errors String
    -> Form.Validation.Field String parsed kind
    -> Html.Html msg
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
