module Route.Date.SPLAT_ exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Exception exposing (Throwable)
import Head
import Html.Styled exposing (text)
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { splat : ( String, List String ) }


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data

        --, routeFound = \_ -> DataSource.succeed True
        }
        |> RouteBuilder.buildNoState { view = view }


pages : DataSource Throwable (List RouteParams)
pages =
    DataSource.succeed
        [ { splat = ( "2021", [ "04", "28" ] )
          }
        , { splat = ( "2021-04-28", [] )
          }
        ]


data : RouteParams -> DataSource Throwable Data
data routeParams =
    DataSource.succeed {}


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


type alias Data =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { body =
        [ Debug.toString static.routeParams |> text
        ]
    , title = ""
    }
