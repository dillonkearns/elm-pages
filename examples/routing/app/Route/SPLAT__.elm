module Route.SPLAT__ exposing (Data, Model, Msg, route)

import DataSource
import Head
import Html.Styled exposing (text)
import Pages.PageUrl exposing (PageUrl)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { splat : List String }


route : StatelessRoute RouteParams Data
route =
    RouteBuilder.preRender
        { head = head
        , pages = DataSource.succeed []
        , data = data

        --, routeFound = \_ -> DataSource.succeed True
        }
        |> RouteBuilder.buildNoState { view = view }


data : RouteParams -> DataSource.DataSource Data
data routeParams =
    DataSource.succeed {}


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    []


type alias Data =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { body =
        [ Debug.toString static.routeParams |> text
        ]
    , title = "Fallback splat page"
    }
