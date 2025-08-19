module Route.Form exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Date exposing (Date)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Html.Styled
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type Msg
    = FirstNameUpdated String


type alias RouteParams =
    {}


type alias ActionData =
    { user : User
    , formResponse : Form.ServerResponse String
    }


type alias User =
    { first : String
    , last : String
    , username : String
    , email : String
    , birthDay : Date
    , checkbox : Bool
    }


defaultUser : User
defaultUser =
    { first = "Jane"
    , last = "Doe"
    , username = "janedoe"
    , email = "janedoe@example.com"
    , birthDay = Date.fromCalendarDate 1969 Time.Jul 20
    , checkbox = False
    }


form : Form.HtmlForm String User User (PagesMsg Msg)
form =
    Form.form
        (\first last username email dob check ->
            { combine =
                Validation.succeed User
                    |> Validation.andMap first
                    |> Validation.andMap last
                    |> Validation.andMap username
                    |> Validation.andMap email
                    |> Validation.andMap dob
                    |> Validation.andMap check
            , view =
                \formState ->
                    let
                        errors : Validation.Field String parsed kind -> List String
                        errors field =
                            formState.errors
                                |> Form.errorsForField field

                        errorsView : Validation.Field String parsed kind -> Html msg
                        errorsView field =
                            case ( formState.submitAttempted, field |> errors ) of
                                ( True, firstItem :: rest ) ->
                                    Html.div []
                                        [ Html.ul
                                            [ Attr.style "border" "solid red"
                                            ]
                                            (List.map
                                                (\error ->
                                                    Html.li []
                                                        [ Html.text error
                                                        ]
                                                )
                                                (firstItem :: rest)
                                            )
                                        ]

                                _ ->
                                    Html.div [] []

                        fieldView : String -> Validation.Field String parsed Form.FieldView.Input -> Html msg
                        fieldView label field =
                            Html.div []
                                [ Html.label []
                                    [ Html.text (label ++ " ")
                                    , field |> Form.FieldView.input []
                                    ]
                                , errorsView field
                                ]
                    in
                    [ fieldView "First" first
                    , fieldView "Last" last
                    , fieldView "Price" username
                    , fieldView "Image" email
                    , fieldView "Image" dob
                    , Html.button [ Attr.id "update" ]
                        [ Html.text
                            (if formState.submitting then
                                "Updating..."

                             else
                                "Update"
                            )
                        ]
                    ]
            }
        )
        |> Form.field "first"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue .first
            )
        |> Form.field "last"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue .last
            )
        |> Form.field "username"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue .username
             --|> Form.withServerValidation
             --    (\username ->
             --        if username == "asdf" then
             --            BackendTask.succeed [ "username is taken" ]
             --
             --        else
             --            BackendTask.succeed []
             --    )
            )
        |> Form.field "email"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue .email
            )
        |> Form.field "dob"
            (Field.date
                { invalid = \_ -> "Invalid date"
                }
                |> Field.required "Required"
                |> Field.withInitialValue .birthDay
             --|> Field.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date)
             --|> Field.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
            )
        |> Form.field "checkbox" Field.checkbox


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { init = init
            , update = update
            , subscriptions = \_ _ _ _ -> Sub.none
            , view = view
            }


type alias Data =
    {}


data : RouteParams -> Request -> BackendTask FatalError (Server.Response.Response Data ErrorPage)
data routeParams request =
    Data
        |> Server.Response.render
        |> BackendTask.succeed


action : RouteParams -> Request -> BackendTask FatalError (Server.Response.Response ActionData ErrorPage)
action routeParams request =
    case request |> Request.formData (form |> Form.Handler.init identity) of
        Nothing ->
            "Expected form submission." |> FatalError.fromString |> BackendTask.fail

        Just ( formResponse, userResult ) ->
            ActionData
                (userResult
                    |> Form.toResult
                    -- TODO nicer error handling
                    -- TODO wire up BackendTask server-side validation errors
                    |> Result.withDefault defaultUser
                )
                formResponse
                |> Server.Response.render
                |> BackendTask.succeed


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect msg )
init _ _ =
    ( {}, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect msg )
update _ _ msg model =
    case msg of
        FirstNameUpdated new ->
            ( model
            , Effect.SetField
                { formId = "user-form", name = "first", value = new }
            )


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared _ =
    let
        user : User
        user =
            app.action
                |> Maybe.map .user
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ app.action
            |> Maybe.map .user
            |> Maybe.map
                (\user_ ->
                    Html.p
                        [ Attr.style "padding" "10px"
                        , Attr.style "background-color" "#a3fba3"
                        ]
                        [ Html.text <| "Successfully received user " ++ user_.first ++ " " ++ user_.last
                        ]
                )
            |> Maybe.withDefault (Html.p [] [])
        , Html.h1
            []
            [ Html.text <| "Edit profile " ++ user.first ++ " " ++ user.last ]
        , form
            |> Pages.Form.renderHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                (Form.options "user-form"
                    |> Form.withInput defaultUser
                    |> Form.withServerResponse (app.action |> Maybe.map .formResponse)
                )
                app
        , Html.button
            [ Html.Events.onClick <|
                PagesMsg.fromMsg <|
                    FirstNameUpdated "Jim"
            , Attr.style "width" "100%"
            , Attr.id "fill-jim"
            ]
            [ Html.text "Set first name to Jim" ]
        ]
            |> List.map Html.Styled.fromUnstyled
    }
