module Route.FileData exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled exposing (text)
import Json.Decode as Decode
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
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
        |> BackendTask.allowFatal
        |> BackendTask.map Data


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
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
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Index page"
    , body =
        [ text <| "Greeting: " ++ app.data.greeting
        ]
    }
