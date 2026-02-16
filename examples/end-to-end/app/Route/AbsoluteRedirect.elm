module Route.AbsoluteRedirect exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Validation as Validation
import Head
import Html.Styled as Html
import Pages.Form
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import Url
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias StaticData =
    ()


type alias Data =
    {}


type alias ActionData =
    {}


form : Form.StyledHtmlForm String () () (PagesMsg Msg)
form =
    Form.form
        { combine =
            Validation.succeed ()
        , view =
            \formState ->
                [ Html.button []
                    [ Html.text
                        (if formState.submitting then
                            "Submitting..."

                         else
                            "Submit Absolute Redirect"
                        )
                    ]
                ]
        }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data _ _ =
    BackendTask.succeed (Response.render {})


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action _ request =
    let
        redirectTarget : String
        redirectTarget =
            case request |> Request.rawUrl |> Url.fromString of
                Just parsedUrl ->
                    toOrigin parsedUrl ++ "/hello"

                Nothing ->
                    "/hello"
    in
    redirectTarget
        |> Response.temporaryRedirect
        |> BackendTask.succeed


toOrigin : Url.Url -> String
toOrigin parsedUrl =
    protocolToString parsedUrl.protocol
        ++ parsedUrl.host
        ++ (parsedUrl.port_
                |> Maybe.map (\port_ -> ":" ++ String.fromInt port_)
                |> Maybe.withDefault ""
           )


protocolToString : Url.Protocol -> String
protocolToString protocol =
    case protocol of
        Url.Http ->
            "http://"

        Url.Https ->
            "https://"


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head _ =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app _ =
    { title = "Absolute Redirect"
    , body =
        [ Html.p []
            [ Html.text "Submits a POST with an empty body and redirects to an absolute URL."
            ]
        , form
            |> Pages.Form.renderStyledHtml
                []
                (Form.options "absolute-redirect")
                app
        ]
    }

