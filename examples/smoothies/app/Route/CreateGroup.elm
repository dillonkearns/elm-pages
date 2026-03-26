module Route.CreateGroup exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Description exposing (Description)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation exposing (Validation)
import GroupName exposing (GroupName)
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
    case request |> Request.formData (postForm |> Form.Handler.init identity) of
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
    { title = "Create Group"
    , body =
        [ postForm
            |> Pages.Form.renderStyledHtml []
                (Form.options "create-group")
                app
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


postForm : Form.StyledHtmlForm String GroupFormValidated data msg
postForm =
    Form.form
        (\name description visibility ->
            { combine =
                Validation.succeed GroupFormValidated
                    |> Validation.andMap name
                    |> Validation.andMap description
                    |> Validation.andMap visibility
            , view =
                \formState ->
                    [ Html.h2 [] [ Html.text "Create a group" ]
                    , fieldView formState "What's the name of your group?" name
                    , fieldView formState "Describe what your group is about (you can fill out this later)" description
                    , Html.div []
                        [ Form.FieldView.radioStyled []
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
                        [ Attr.disabled formState.submitting
                        ]
                        [ Html.text
                            (if formState.submitting then
                                "Submitting..."

                             else
                                "Submit"
                            )
                        ]
                    ]
            }
        )
        |> Form.field "name"
            (Field.text
                |> Field.required "Required"
                |> Field.validateMap
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
                    )
            )
        |> Form.field "description"
            (Field.text
                |> Field.textarea { rows = Nothing, cols = Nothing }
                |> Field.validateMap
                    (\value ->
                        value
                            |> Maybe.withDefault ""
                            |> Description.fromString
                            |> Result.mapError Description.errorToString
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
    -> Validation.Field String parsed Form.FieldView.Input
    -> Html msg
fieldView formState label field =
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Form.FieldView.inputStyled []
            ]
        , errorsForField formState field
        ]


errorsForField : Form.Context String data -> Validation.Field String parsed kind -> Html msg
errorsForField formState field =
    (if formState.submitAttempted then
        formState.errors
            |> Form.errorsForField field
            |> List.map (\error -> Html.li [] [ Html.text error ])

     else
        []
    )
        |> Html.ul [ Attr.style "color" "red" ]


