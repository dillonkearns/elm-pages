module Route.Rgb.Red_.Green_.Blue_ exposing (Data, Model, Msg, page)

import ColorHelpers
import DataSource exposing (DataSource)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { red : String, green : String, blue : String }


page : StatelessRoute RouteParams Data
page =
    RouteBuilder.preRenderWithFallback
        { head = ColorHelpers.head toCssVal
        , pages = pages
        , data = ColorHelpers.data
        }
        |> RouteBuilder.buildNoState { view = ColorHelpers.view toCssVal }


pages : DataSource (List RouteParams)
pages =
    DataSource.succeed []


type alias Data =
    ColorHelpers.Data


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
