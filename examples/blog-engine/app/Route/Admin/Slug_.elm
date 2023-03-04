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
import Html exposing (Html)
import Html.Attributes
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import PagesMsg exposing (PagesMsg)
import Path
import Platform.Sub
import Post exposing (Post)
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
    -> Path.Path
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions routeParams path shared model =
    Sub.none


type alias Data =
    { post : Post
    }


type alias ActionData =
    { errors : Form.Response String }


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
            |> Form.renderHtml "form" [] (Just << .errors) app app.data.post
        , if app.routeParams.slug == "new" then
            Html.text ""

          else
            deleteForm
                |> Form.renderHtml "delete" [] (\_ -> Nothing) app ()
        ]
    }


action :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.map
        (\( formResponse, parsedForm ) ->
            case parsedForm of
                Ok Delete ->
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

                Ok (CreateOrEdit okForm) ->
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
        (Server.Request.formData formHandlers)


form : Form.HtmlForm String Post Post Msg
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
        |> Form.init
        |> Form.hiddenKind ( "kind", "create-or-edit" ) "Expected create-or-edit"
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
            (Form.Field.date { invalid = \_ -> "Invalid date." }
                |> Form.Field.withOptionalInitialValue
                    (.publish >> Maybe.map Form.Value.date)
            )


type Action
    = Delete
    | CreateOrEdit Post


formHandlers : Form.ServerForms String Action
formHandlers =
    deleteForm
        |> Form.initCombined (\() -> Delete)
        |> Form.combine CreateOrEdit form


deleteForm : Form.HtmlForm String () input Msg
deleteForm =
    Form.init
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


buttonWithTransition : List (Html.Attribute msg) -> String -> String -> { a | isTransitioning : Bool } -> Html msg
buttonWithTransition attributes initialText transitioningText formState =
    if formState.isTransitioning then
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
    -> Html.Html (PagesMsg Msg)
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
