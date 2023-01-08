module Route.Named.Color_ exposing (ActionData, Data, Model, Msg, route)

import ColorHelpers
import BackendTask exposing (BackendTask)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)


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


route : StatelessRoute RouteParams Data ActionData
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


pages : BackendTask (List RouteParams)
pages =
    BackendTask.succeed []
