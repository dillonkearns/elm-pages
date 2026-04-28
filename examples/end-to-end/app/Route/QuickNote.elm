module Route.QuickNote exposing (ActionData, Data, Model, Msg, route)

{-| A route with a concurrent (fetcher) form submission.
The form submits without blocking navigation, and the submission
status is tracked in concurrentSubmissions.
-}

import BackendTask exposing (BackendTask)
import Dict
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation
import Html.Styled as Html
import Pages.ConcurrentSubmission
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
    {}


type alias ActionData =
    { note : String
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
    BackendTask.succeed (Response.render {})


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    case request |> Request.formData (form |> Form.Handler.init identity) of
        Just ( formResponse, validated ) ->
            let
                noteValue =
                    validated
                        |> Form.toResult
                        |> Result.withDefault (Just "(error)")
                        |> Maybe.withDefault "(empty)"
            in
            { note = noteValue }
                |> Response.render
                |> BackendTask.succeed

        Nothing ->
            { note = "No form data" }
                |> Response.render
                |> BackendTask.succeed


form : Form.StyledHtmlForm String (Maybe String) input msg
form =
    Form.form
        (\note ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap note
            , view =
                \formState ->
                    [ Html.div []
                        [ Html.label []
                            [ Html.text "Note: "
                            , note |> Form.FieldView.inputStyled []
                            ]
                        ]
                    , Html.button []
                        [ Html.text "Save Note" ]
                    ]
            }
        )
        |> Form.field "note" Field.text


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Quick Note"
    , body =
        [ Html.h1 [] [ Html.text "Quick Note" ]
        , form
            |> Pages.Form.renderStyledHtml []
                (Form.options "note-form"
                    |> Pages.Form.withConcurrent
                )
                app
        , Html.div []
            (app.concurrentSubmissions
                |> Dict.toList
                |> List.map
                    (\( key, submission ) ->
                        Html.p []
                            [ case submission.status of
                                Pages.ConcurrentSubmission.Submitting ->
                                    Html.text "Saving..."

                                Pages.ConcurrentSubmission.Reloading actionData ->
                                    case actionData of
                                        Just ad ->
                                            Html.text ("Saved: " ++ ad.note)

                                        Nothing ->
                                            Html.text "Saved!"

                                Pages.ConcurrentSubmission.Complete actionData ->
                                    case actionData of
                                        Just ad ->
                                            Html.text ("Done: " ++ ad.note)

                                        Nothing ->
                                            Html.text "Done!"
                            ]
                    )
            )
        ]
    }
