module Route.Hex.Hex_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ColorHelpers
import Exception exposing (Throwable)
import RouteBuilder exposing (StatelessRoute, StaticPayload)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { hex : String }


type alias Data =
    ColorHelpers.Data


type alias ActionData =
    {}


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
    "#" ++ routeParams.hex


pages : BackendTask Throwable (List RouteParams)
pages =
    BackendTask.succeed []
