module Route.Index exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import FrozenHelper
import Head
import Html.Styled as Html
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Ui.ListViewA as ListViewA
import Ui.ListViewB as ListViewB
import Ui.ListViewC as ListViewC
import Ui.ListViewD as ListViewD
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
    { users : List { name : String }
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
        { users = [ { name = "Alice" }, { name = "Bob" } ]
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
    { title = "Frozen Helper Seeding Fixture (Unsupported overflow diagnostics)"
    , body =
        [ Html.h1 [] [ Html.text "Unsupported overflow diagnostics matrix" ] ]
            ++ (app.data.users |> List.map FrozenHelper.summaryCard)
            ++ ListViewA.summaryCardsA app.data.users
            ++ ListViewB.summaryCardsB app.data.users
            ++ ListViewC.summaryCardsC app.data.users
            ++ ListViewD.summaryCardsD app.data.users
    }
