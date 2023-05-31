module Page.Index exposing (Data, Model, Msg, page)

import BackendTask exposing (BackendTask)
import Head
import Head.Seo as Seo
import RouteBuilder exposing (StatelessRoute, StatefulRoute, App)
import Pages.Url
import View exposing (View)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    {}


page : StatelessRoute RouteParams Data ActionData
page =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()


head :
    App Data ActionData RouteParams
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


type alias Data =
    ()


view :
    App Data ActionData RouteParams
    -> View Msg
view static =
    View.placeholder "Index"
