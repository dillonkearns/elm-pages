module Page.Date.SPLAT_ exposing (Data, Model, Msg, page)

import DataSource
import Head
import Html.Styled exposing (text)
import RouteBuilder exposing (StatelessRoute, StatefulRoute, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    Never


type alias RouteParams =
    { splat : ( String, List String ) }


page : StatelessRoute RouteParams Data
page =
    Page.preRender
        { head = head
        , pages = pages
        , data = data

        --, routeFound = \_ -> DataSource.succeed True
        }
        |> RouteBuilder.buildNoState { view = view }


pages : DataSource.DataSource (List RouteParams)
pages =
    DataSource.succeed
        [ { splat = ( "2021", [ "04", "28" ] )
          }
        , { splat = ( "2021-04-28", [] )
          }
        ]


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
    , title = ""
    }
