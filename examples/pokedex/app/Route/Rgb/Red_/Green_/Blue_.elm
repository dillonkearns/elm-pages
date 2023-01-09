module Route.Rgb.Red_.Green_.Blue_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ColorHelpers
import Exception exposing (Throwable)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { red : String, green : String, blue : String }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRenderWithFallback
        { head = ColorHelpers.head toCssVal
        , pages = pages
        , data = ColorHelpers.data
        }
        |> RouteBuilder.buildNoState { view = ColorHelpers.view toCssVal }


pages : BackendTask Throwable (List RouteParams)
pages =
    BackendTask.succeed []


type alias Data =
    ColorHelpers.Data


type alias ActionData =
    {}


toCssVal : RouteParams -> String
toCssVal routeParams =
    "rgb("
        ++ ([ routeParams.red
            , routeParams.green
            , routeParams.blue
            ]
                |> String.join " "
           )
        ++ " / 1)"
