module Route.Date.SPLAT_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Html.Styled exposing (text)
import PagesMsg exposing (PagesMsg)
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

        --, routeFound = \_ -> BackendTask.succeed True
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask FatalError (List RouteParams)
pages =
    BackendTask.succeed
        [ { splat = ( "2021", [ "04", "28" ] )
          }
        , { splat = ( "2021-04-28", [] )
          }
        ]


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    BackendTask.succeed {}


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
    -> View (PagesMsg Msg)
view maybeUrl sharedModel static =
    { body =
        [ Debug.toString static.routeParams |> text
        ]
    , title = ""
    }
