module Route.PortTest exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.Port
import Head
import Head.Seo as Seo
import Html
import Json.Decode as Decode
import Json.Encode as Encode
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


page : Page RouteParams Data
page =
    Page.single
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Data =
    { portGreeting : String
    }


data : DataSource Data
data =
    DataSource.succeed Data
        |> DataSource.andMap (DataSource.Port.get "hello" (Encode.string "Jane") Decode.string)


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Placeholder"
    , body = [ Html.text static.data.portGreeting ]
    }
