module Route.SPLAT__ exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Html.Styled exposing (text)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { splat : List String }


type alias ActionData =
    {}


type alias StaticData =
    ()


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = BackendTask.succeed []
        , data = data

        --, routeFound = \_ -> BackendTask.succeed True
        }
        |> RouteBuilder.buildNoState { view = view }


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    BackendTask.succeed {}


head :
    App Data () ActionData RouteParams
    -> List Head.Tag
head app =
    []


type alias Data =
    {}


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { body =
        [ Debug.toString app.routeParams |> text
        ]
    , title = "Fallback splat page"
    }
