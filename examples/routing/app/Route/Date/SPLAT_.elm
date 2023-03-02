module Route.Date.SPLAT_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Html.Styled exposing (text)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
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
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    []


type alias Data =
    {}


view :
    Shared.Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view shared app =
    { body =
        [ Debug.toString app.routeParams |> text
        ]
    , title = ""
    }
