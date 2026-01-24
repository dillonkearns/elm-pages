module Route.Named.Color_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ColorHelpers
import FatalError exposing (FatalError)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { color : String }


type alias ActionData =
    {}


type alias Data =
    ColorHelpers.Data


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.preRenderWithFallback
        { head = ColorHelpers.head toCssVal
        , pages = pages
        , data = ColorHelpers.data
        }
        |> RouteBuilder.buildNoState { view = ColorHelpers.view toCssVal }


toCssVal : RouteParams -> String
toCssVal routeParams =
    routeParams.color


pages : BackendTask FatalError (List RouteParams)
pages =
    BackendTask.succeed []
