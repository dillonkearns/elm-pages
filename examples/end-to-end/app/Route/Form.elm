module Route.Form exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Date exposing (Date)
import ErrorPage exposing (ErrorPage)
import Form exposing (Form)
import Form.Value
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Styled
import Html.Styled.Attributes as StyledAttr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
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
    {}


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


errorsView : List String -> Html msg
errorsView errors =
    case errors of
        first :: rest ->
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
                        (first :: rest)
                    )
                ]

        [] ->
            Html.div [] []


form : User -> Form (Pages.Msg.Msg Msg) String User (Html (Pages.Msg.Msg Msg))
form user =
    Form.succeed User
        |> Form.with
            (Form.text
                "first"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label toLabel
                            [ Html.text "First"
                            ]
                        , Html.input toInput []
                        ]
                )
                |> Form.required "Required"
                |> Form.withInitialValue (user.first |> Form.Value.string)
            )
        |> Form.with
            (Form.text
                "last"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label toLabel
                            [ Html.text "Last"
                            ]
                        , Html.input toInput []
                        ]
                )
                |> Form.required "Required"
                |> Form.withInitialValue (user.last |> Form.Value.string)
            )
        |> Form.with
            (Form.text
                "username"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label toLabel
                            [ Html.text "Username"
                            ]
                        , Html.input toInput []
                        ]
                )
                |> Form.required "Required"
                |> Form.withInitialValue (user.username |> Form.Value.string)
                |> Form.withServerValidation
                    (\username ->
                        if username == "asdf" then
                            DataSource.succeed [ "username is taken" ]

                        else
                            DataSource.succeed []
                    )
            )
        |> Form.with
            (Form.text
                "email"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label toLabel
                            [ Html.text "Email"
                            ]
                        , Html.input toInput []
                        ]
                )
                |> Form.required "Required"
             --|> Form.withInitialValue (user.email |> Form.Value.string)
            )
        |> Form.with
            (Form.date
                "dob"
                { invalid = \_ -> "Invalid date"
                }
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label toLabel
                            [ Html.text "Date of Birth"
                            ]
                        , Html.input toInput []
                        ]
                )
                |> Form.required "Required"
                --|> Form.withInitialValue (user.birthDay |> Form.Value.date)
                |> Form.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date)
                |> Form.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
            )
        |> Form.with
            (Form.checkbox
                "checkbox"
                user.checkbox
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label toLabel
                            [ Html.text "Checkbox"
                            ]
                        , Html.input toInput []
                        ]
                )
            )
        |> Form.append
            (Form.submit
                (\{ attrs } ->
                    Html.input attrs []
                )
            )


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip ""
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { user : Maybe User
    , errors : Form.Model
    }


data : RouteParams -> Parser (DataSource (Server.Response.Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Form.submitHandlers
            (form defaultUser)
            (\model decoded ->
                case decoded of
                    Ok okUser ->
                        Route.Form
                            |> Route.redirectTo
                            |> DataSource.succeed

                    Err _ ->
                        { user = Nothing
                        , errors = model
                        }
                            |> Server.Response.render
                            |> DataSource.succeed
            )
        , { user = Nothing
          , errors = Form.init (form defaultUser)
          }
            |> Server.Response.render
            |> DataSource.succeed
            |> Request.succeed
        ]


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    let
        user : User
        user =
            static.data.user
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ static.data.user
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

        -- TODO replace with new form API
        , Form.toStatelessHtml Nothing Html.form static.data.errors (form user)
        ]
            |> List.map Html.Styled.fromUnstyled
    }
