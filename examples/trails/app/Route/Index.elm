module Route.Index exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import DataSource.Env as Env
import DataSource.Http
import Head
import Head.Seo as Seo
import Html exposing (..)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
import RouteBuilder exposing (StatelessRoute, StaticPayload)
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
    {}


type alias ActionData =
    {}


data : DataSource Data
data =
    DataSource.succeed {}


head :
    StaticPayload Data RouteParams ActionData
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages Pokedex"
        , image =
            { url = Pages.Url.external ""
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "This is a simple app to showcase server-rendering with elm-pages."
        , locale = Nothing
        , title = "Elm Pages Pokedex Example"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams ActionData
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "Pokedex"
    , body =
        []
    }
