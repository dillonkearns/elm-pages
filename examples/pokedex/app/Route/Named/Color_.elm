module Route.Named.Color_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ColorHelpers
import Exception exposing (Throwable)
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


pages : BackendTask Throwable (List RouteParams)
pages =
    BackendTask.succeed []
