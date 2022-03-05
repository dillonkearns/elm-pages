module Route.Hex.Hex_ exposing (Data, Model, Msg, page)

import ColorHelpers
import DataSource exposing (DataSource)
import RouteBuilder exposing (StatelessRoute, StaticPayload)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { hex : String }


type alias Data =
    ColorHelpers.Data


page : StatelessRoute RouteParams Data
page =
    RouteBuilder.preRenderWithFallback
        { head = ColorHelpers.head toCssVal
        , pages = pages
        , data = ColorHelpers.data
        }
        |> RouteBuilder.buildNoState { view = ColorHelpers.view toCssVal }


toCssVal : RouteParams -> String
toCssVal routeParams =
    "#" ++ routeParams.hex


pages : DataSource (List RouteParams)
pages =
    DataSource.succeed []
