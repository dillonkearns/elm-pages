module Route.Blog.Slug_ exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled as Html
import Pages.PageUrl exposing (PageUrl)
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
    { slug : String }


type alias ActionData =
    {}


type alias StaticData =
    ()


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask FatalError (List RouteParams)
pages =
    BackendTask.succeed []


type alias Data =
    {}


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    BackendTask.succeed {}


head :
    App Data () ActionData RouteParams
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
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view static sharedModel =
    { title = "Blog.Slug_"
    , body = [ Html.text "Blog.Slug_" ]
    }
