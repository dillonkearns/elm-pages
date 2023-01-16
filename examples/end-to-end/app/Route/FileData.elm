module Route.FileData exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import BuildError exposing (BuildError)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled exposing (text)
import Json.Decode as Decode
import Pages.Msg
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


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    }


data : BackendTask FatalError Data
data =
    "my-json-data.json"
        |> BackendTask.File.jsonFile (Decode.field "greeting" Decode.string)
        |> BackendTask.throw
        |> BackendTask.map Data


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "Index page"
    , body =
        [ text <| "Greeting: " ++ static.data.greeting
        ]
    }
