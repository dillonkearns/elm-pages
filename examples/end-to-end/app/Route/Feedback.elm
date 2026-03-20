module Route.Feedback exposing (ActionData, Data, Model, Msg, route)

{-| Form route that reads/writes a file to demonstrate the framework
data refresh lifecycle. The `data` BackendTask reads "feedback.txt",
the `action` writes to it, and after submission the framework
automatically re-resolves `data` showing the updated file content.
-}

import BackendTask exposing (BackendTask)
import BackendTask.File
import BackendTask.Stream as Stream
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation
import Html.Styled as Html
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    { fileContent : String
    }


type alias ActionData =
    { message : String
    }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \_ -> []
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.File.rawFile "feedback.txt"
        |> BackendTask.allowFatal
        |> BackendTask.map (\content -> Response.render { fileContent = content })


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    case request |> Request.formData (form |> Form.Handler.init identity) of
        Just ( formResponse, validated ) ->
            let
                messageValue =
                    validated
                        |> Form.toResult
                        |> Result.withDefault (Just "(validation error)")
                        |> Maybe.withDefault "(empty)"
            in
            Stream.fromString messageValue
                |> Stream.pipe (Stream.fileWrite "feedback.txt")
                |> Stream.run
                |> BackendTask.map
                    (\() ->
                        Response.render { message = messageValue }
                    )

        Nothing ->
            { message = "No form data received" }
                |> Response.render
                |> BackendTask.succeed


form : Form.StyledHtmlForm String (Maybe String) input msg
form =
    Form.form
        (\message ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap message
            , view =
                \formState ->
                    [ Html.div []
                        [ Html.label []
                            [ Html.text "Message: "
                            , message |> Form.FieldView.inputStyled []
                            ]
                        ]
                    , Html.button []
                        [ Html.text "Submit Feedback" ]
                    ]
            }
        )
        |> Form.field "message" Field.text


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Feedback"
    , body =
        [ Html.h1 [] [ Html.text "Feedback Form" ]
        , Html.p []
            [ Html.text ("Current file: " ++ app.data.fileContent) ]
        , case app.action of
            Just actionData ->
                Html.p []
                    [ Html.text ("You said: " ++ actionData.message) ]

            Nothing ->
                Html.text ""
        , form
            |> Pages.Form.renderStyledHtml []
                (Form.options "feedback-form")
                app
        ]
    }
