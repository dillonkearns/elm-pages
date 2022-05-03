module Route.PortTest exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import DataSource.Port
import Head
import Head.Seo as Seo
import Html
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { portGreeting : String
    }


type alias ActionData =
    {}


data : DataSource Data
data =
    DataSource.succeed Data
        |> DataSource.andMap (DataSource.Port.get "hello" (Encode.string "Jane") Decode.string)


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Placeholder"
    , body = [ Html.text static.data.portGreeting ]
    }
