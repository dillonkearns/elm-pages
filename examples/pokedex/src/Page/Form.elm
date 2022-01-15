module Page.Form exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict exposing (Dict)
import Form exposing (Form)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Page exposing (Page, PageWithState, StaticPayload)
import PageServerResponse exposing (PageServerResponse)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Server.Request as Request exposing (Request)
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
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


form : User -> Form String User (Html Form.Msg)
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
                |> Form.withInitialValue user.first
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
                |> Form.withInitialValue user.last
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
                |> Form.withInitialValue user.username
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
                |> Form.withInitialValue user.email
            )
        |> Form.with
            (Form.requiredDate
                "dob"
                { missing = "Required"
                , invalid = \_ -> "Invalid date"
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
                |> Form.withInitialValue (user.birthDay |> Date.toIsoString)
                |> Form.withMinDate (Date.fromCalendarDate 1900 Time.Jan 1)
                |> Form.withMaxDate (Date.fromCalendarDate 2022 Time.Jan 1)
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


page : Page RouteParams Data
page =
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Data =
    { user : Maybe User
    , errors : Maybe Form.ServerUpdate
    }


data : RouteParams -> Request (DataSource (PageServerResponse Data))
data routeParams =
    Request.oneOf
        [ Form.toRequest2 (form defaultUser)
            |> Request.map
                (\userOrErrors ->
                    userOrErrors
                        |> DataSource.map
                            (\result ->
                                (case result of
                                    Ok ( errors, user ) ->
                                        { user = Just user
                                        , errors = Just errors
                                        }

                                    Err errors ->
                                        { user = Nothing
                                        , errors = Just errors
                                        }
                                )
                                    |> PageServerResponse.RenderPage
                            )
                )
        , PageServerResponse.RenderPage
            { user = Nothing
            , errors = Nothing
            }
            |> DataSource.succeed
            |> Request.succeed
        ]


head :
    StaticPayload Data RouteParams
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
    -> StaticPayload Data RouteParams
    -> View Msg
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
        , form user
            |> Form.toHtml { pageReloadSubmit = True }
                Html.form
                { fields =
                    static.data.errors
                        |> Maybe.withDefault (Form.init (form defaultUser) |> .fields)
                , isSubmitting = Form.NotSubmitted
                , formErrors = Dict.empty
                }
            |> Html.map (\_ -> ())
        ]
    }
