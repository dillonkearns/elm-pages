module Route.Index exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Html.Styled as Html
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Ui.ListView as ListView
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
    { greeting : String
    , users : List { name : String }
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
        { greeting = "Hello"
        , users = [ { name = "Alice" }, { name = "Bob" } ]
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
    { title = "Frozen Helper Seeding Fixture (Mixed supported + unsupported in lib/)"
    , body =
        [ View.freeze (Html.div [] [ Html.text ("Direct: " ++ app.data.greeting) ])
        ]
            ++ ListView.summaryCards app.data.users
    }
