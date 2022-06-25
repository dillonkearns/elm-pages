module Route.CreateGroup exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Description exposing (Description)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import GroupName exposing (GroupName)
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
import Validation
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
    Request.formParserResultNew [ postForm ]
        |> Request.map
            (\parsedForm ->
                let
                    _ =
                        Debug.log "parsedForm"
                            (case parsedForm of
                                Ok group ->
                                    "Got valid group: " ++ Debug.toString group

                                Err formErrors ->
                                    "Got from errors: " ++ Debug.toString formErrors
                            )
                in
                DataSource.succeed (Response.render ActionData)
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
    { title = "Create Group"
    , body =
        [ Form.renderHtml { method = Form.Post, submitStrategy = Form.TransitionStrategy } app () postForm
        ]
    }


type alias GroupFormValidated =
    { name : GroupName
    , description : Description
    , visibility : GroupVisibility
    }


type GroupVisibility
    = UnlistedGroup
    | PublicGroup


postForm : Form.HtmlForm String GroupFormValidated data Msg
postForm =
    Form.init
        (\name description visibility ->
            Validation.succeed GroupFormValidated
                |> Validation.withField name
                |> Validation.withField description
                |> Validation.withField visibility
        )
        (\formState name description visibility ->
            ( []
            , [ Html.h2 [] [ Html.text "Create a group" ]
              , fieldView formState "What's the name of your group?" name
              , fieldView formState "Describe what your group is about (you can fill out this later)" description
              , Html.div []
                    [ Pages.FieldRenderer.radio []
                        (\enum toRadio ->
                            Html.div []
                                [ Html.label []
                                    [ toRadio []
                                    , Html.text
                                        (case enum of
                                            UnlistedGroup ->
                                                "I want this group to be unlisted (people can only find it if you link it to them)"

                                            PublicGroup ->
                                                "I want this group to be publicly visible"
                                        )
                                    ]
                                ]
                        )
                        visibility
                    , errorsForField formState visibility
                    ]
              , Html.button
                    [ Attr.disabled formState.isTransitioning
                    ]
                    [ Html.text
                        (if formState.isTransitioning then
                            "Submitting..."

                         else
                            "Submit"
                        )
                    ]
              ]
            )
        )
        |> Form.field "name"
            (Field.text
                |> Field.required "Required"
                |> Field.withClientValidation
                    (\value ->
                        value
                            |> GroupName.fromString
                            |> Result.mapError
                                (\error ->
                                    case error of
                                        GroupName.GroupNameTooShort ->
                                            "Name must be at least "
                                                ++ String.fromInt GroupName.minLength
                                                ++ " characters long."

                                        GroupName.GroupNameTooLong ->
                                            "Name is too long. Keep it under "
                                                ++ String.fromInt (GroupName.maxLength + 1)
                                                ++ " characters."
                                )
                            |> fromResult
                    )
            )
        |> Form.field "description"
            (Field.text
                |> Field.textarea
                |> Field.withClientValidation
                    (\value ->
                        value
                            |> Maybe.withDefault ""
                            |> Description.fromString
                            |> Result.mapError Description.errorToString
                            |> fromResult
                    )
            )
        |> Form.field "visibility"
            (Field.select
                [ ( "unlisted", UnlistedGroup )
                , ( "public", PublicGroup )
                ]
                (\_ -> "Invalid")
                |> Field.required "Pick a visibility setting"
            )


fieldView :
    Form.Context String data
    -> String
    -> Form.ViewField String parsed Pages.FieldRenderer.Input
    -> Html msg
fieldView formState label field =
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Pages.FieldRenderer.input []
            ]
        , errorsForField formState field
        ]


errorsForField : Form.Context String data -> Form.ViewField String parsed kind -> Html msg
errorsForField formState field =
    (if formState.submitAttempted then
        field.errors
            |> List.map (\error -> Html.li [] [ Html.text error ])

     else
        []
    )
        |> Html.ul [ Attr.style "color" "red" ]


fromResult : Result error value -> ( Maybe value, List error )
fromResult result =
    case result of
        Ok value ->
            ( Just value, [] )

        Err error ->
            ( Nothing, [ error ] )
