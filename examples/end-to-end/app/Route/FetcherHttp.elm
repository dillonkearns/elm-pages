module Route.FetcherHttp exposing (ActionData, Data, Model, Msg, route)

{-| Minimal route for testing concurrent fetcher HTTP with stale cancellation.
Has HTTP in both data and action functions.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Dict
import ErrorPage
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.Handler
import Form.Validation as Validation
import Html.Styled as Html
import Html.Styled.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.ConcurrentSubmission
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Platform.Sub
import RouteBuilder
import Server.Request as Request exposing (Request)
import Server.Response as Response
import Shared
import View


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    { count : Int }


type alias ActionData =
    {}


route : RouteBuilder.StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \_ -> []
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


data : RouteParams -> Request -> BackendTask FatalError (Response.Response Data ErrorPage.ErrorPage)
data routeParams request =
    BackendTask.Http.getJson
        "https://api.example.com/count"
        (Decode.field "count" Decode.int)
        |> BackendTask.allowFatal
        |> BackendTask.map (\count -> Response.render { count = count })


type Action
    = Increment


action : RouteParams -> Request -> BackendTask FatalError (Response.Response ActionData ErrorPage.ErrorPage)
action routeParams request =
    BackendTask.Http.getJson
        "https://api.example.com/increment"
        (Decode.succeed ())
        |> BackendTask.allowFatal
        |> BackendTask.map (\() -> Response.render {})


incrementForm : Form.StyledHtmlForm String () () (PagesMsg Msg)
incrementForm =
    Form.form
        { combine = Validation.succeed ()
        , view = \_ -> [ Html.button [] [ Html.text "Increment" ] ]
        }
        |> Form.hiddenKind ( "kind", "increment" ) "Expected increment"


forms : Form.Handler.Handler String Action
forms =
    Form.Handler.init (\() -> Increment) incrementForm


view :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> View.View (PagesMsg Msg)
view app sharedModel =
    let
        pendingCount : Int
        pendingCount =
            app.concurrentSubmissions
                |> Dict.values
                |> List.filter
                    (\{ status } ->
                        case status of
                            Pages.ConcurrentSubmission.Complete _ ->
                                False

                            _ ->
                                True
                    )
                |> List.length

        displayCount : Int
        displayCount =
            app.data.count + pendingCount
    in
    { title = "Fetcher HTTP"
    , body =
        [ Html.p [] [ Html.text ("Count: " ++ String.fromInt displayCount) ]
        , incrementForm
            |> Pages.Form.renderStyledHtml []
                (Form.options "increment"
                    |> Pages.Form.withConcurrent
                )
                app
        ]
    }
