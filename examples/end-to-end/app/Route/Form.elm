module Route.Form exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Date exposing (Date)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation
import Form.Value
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Styled
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
import Server.Response
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    { user : User
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


form : Form.HtmlForm String User User Msg
form =
    Form.init
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
                    , Html.button []
                        [ Html.text
                            (if formState.isTransitioning then
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
                |> Field.withInitialValue (.first >> Form.Value.string)
            )
        |> Form.field "last"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (.last >> Form.Value.string)
            )
        |> Form.field "username"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (.username >> Form.Value.string)
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
                |> Field.withInitialValue (.email >> Form.Value.string)
            )
        |> Form.field "dob"
            (Field.date
                { invalid = \_ -> "Invalid date"
                }
                |> Field.required "Required"
                |> Field.withInitialValue (.birthDay >> Form.Value.date)
             --|> Field.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date)
             --|> Field.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
            )
        |> Form.field "checkbox" Field.checkbox


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    {}


data : RouteParams -> Parser (BackendTask FatalError (Server.Response.Response Data ErrorPage))
data routeParams =
    Data
        |> Server.Response.render
        |> BackendTask.succeed
        |> Request.succeed


action : RouteParams -> Parser (BackendTask FatalError (Server.Response.Response ActionData ErrorPage))
action routeParams =
    Request.formData (form |> Form.initCombined identity)
        |> Request.map
            (\( formResponse, userResult ) ->
                ActionData
                    (userResult
                        -- TODO nicer error handling
                        -- TODO wire up BackendTask server-side validation errors
                        |> Result.withDefault defaultUser
                    )
                    |> Server.Response.render
                    |> BackendTask.succeed
            )


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    let
        user : User
        user =
            static.action
                |> Maybe.map .user
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ static.action
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
            |> Form.toDynamicTransition "user-form"
            |> Form.renderHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                (\_ -> Nothing)
                static
                defaultUser
        ]
            |> List.map Html.Styled.fromUnstyled
    }
