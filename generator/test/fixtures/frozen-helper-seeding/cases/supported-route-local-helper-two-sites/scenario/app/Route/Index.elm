module Route.Index exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Html.Styled as Html
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
    { title = "Route-local helper frozen IDs"
    , body =
        [ card app.data.alice
        , card app.data.bob
        ]
    }


card : { name : String } -> Html.Html msg
card user =
    View.freeze (Html.p [] [ Html.text ("User: " ++ user.name) ])
