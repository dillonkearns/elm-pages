module Route.Form exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict
import ErrorPage exposing (ErrorPage)
import Form.Value
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Styled
import Html.Styled.Attributes as StyledAttr
import Pages.Field as Field
import Pages.FieldRenderer
import Pages.Form as Form
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
import Server.Response
import Shared
import Time
import Validation
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
            Validation.succeed User
                |> Validation.withField first
                |> Validation.withField last
                |> Validation.withField username
                |> Validation.withField email
                |> Validation.withField dob
                |> Validation.withField check
        )
        (\formState firstName lastName username email dob check ->
            let
                errors field =
                    formState.errors
                        |> Dict.get field.name
                        |> Maybe.withDefault []

                errorsView field =
                    case ( formState.submitAttempted, field |> errors ) of
                        ( True, first :: rest ) ->
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

                        _ ->
                            Html.div [] []

                fieldView label field =
                    Html.div []
                        [ Html.label []
                            [ Html.text (label ++ " ")
                            , field |> Pages.FieldRenderer.input []
                            ]
                        , errorsView field
                        ]
            in
            ( [ Attr.style "display" "flex"
              , Attr.style "flex-direction" "column"
              , Attr.style "gap" "20px"
              ]
            , [ fieldView "Name" firstName
              , fieldView "Description" lastName
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
            )
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
             --            DataSource.succeed [ "username is taken" ]
             --
             --        else
             --            DataSource.succeed []
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


data : RouteParams -> Parser (DataSource (Server.Response.Response Data ErrorPage))
data routeParams =
    Data
        |> Server.Response.render
        |> DataSource.succeed
        |> Request.succeed


action : RouteParams -> Parser (DataSource (Server.Response.Response ActionData ErrorPage))
action routeParams =
    Request.formParserResultNew [ form ]
        |> Request.map
            (\userResult ->
                ActionData
                    (userResult
                        -- TODO nicer error handling
                        -- TODO wire up DataSource server-side validation errors
                        |> Result.withDefault defaultUser
                    )
                    |> Server.Response.render
                    |> DataSource.succeed
            )


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
        , Form.renderHtml
            { method = Form.Post
            , submitStrategy = Form.TransitionStrategy
            }
            static
            defaultUser
            form
        ]
            |> List.map Html.Styled.fromUnstyled
    }
