module Route.Index exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import FrozenHelper
import Head
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias StaticData =
    ()


type alias Data =
    { alice : { name : String }
    , bob : { name : String }
    }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask FatalError Data
data =
    BackendTask.succeed
        { alice = { name = "Alice" }
        , bob = { name = "Bob" }
        }


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head _ =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app _ =
    { title = "Route + Shared supported helper ID spaces"
    , body =
        [ FrozenHelper.routeCard app.data.alice
        , FrozenHelper.routeCard app.data.bob
        ]
    }
