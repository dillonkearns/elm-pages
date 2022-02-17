module Page.Rgb.Red_.Green_.Blue_ exposing (Data, Model, Msg, page)

import ColorHelpers
import DataSource exposing (DataSource)
import Page exposing (Page, PageWithState, StaticPayload)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { red : String, green : String, blue : String }


page : Page RouteParams Data
page =
    Page.preRenderWithFallback
        { head = ColorHelpers.head toCssVal
        , pages = pages
        , data = ColorHelpers.data
        }
        |> Page.buildNoState { view = ColorHelpers.view toCssVal }


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
