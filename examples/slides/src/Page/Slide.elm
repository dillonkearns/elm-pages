module Page.Slide exposing (Data, Model, Msg, page)

import BackendTask
import Head
import Head.Seo as Seo
import RouteBuilder exposing (StatelessRoute, StatefulRoute, App)
import Shared
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
        , data = BackendTask.succeed ()
        }
        |> RouteBuilder.buildNoState { view = view }


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = ImagePath.build [ "TODO" ]
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
    { title = "TODO title"
    , body = []
    }
