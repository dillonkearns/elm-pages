module Route.ErrorHandling exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html.Styled exposing (text)
import Pages.PageUrl exposing (PageUrl)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
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


type alias ActionData =
    {}


type alias StaticData =
    ()


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> Response.render {} |> BackendTask.succeed
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { darkMode : Maybe String }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.fail
        (FatalError.fromString "This error should be displayed by the error handling!")


head :
    App Data () ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view static sharedModel =
    { title = "Cookie test"
    , body =
        [ case static.data.darkMode of
            Just darkMode ->
                text <|
                    "Dark mode: "
                        ++ darkMode

            Nothing ->
                text "No dark mode preference set"
        ]
    }
