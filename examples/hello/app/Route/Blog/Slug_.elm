module Route.Blog.Slug_ exposing (Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Head
import Head.Seo as Seo
import Html
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { slug : String }


route : StatelessRoute RouteParams Data
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


pages : DataSource (List RouteParams)
pages =
    DataSource.succeed
        [ { slug = "hello" }
        ]


type alias Data =
    { something : String
    }


data : RouteParams -> DataSource Data
data routeParams =
    DataSource.map Data
        (DataSource.succeed "Hi")


head :
    StaticPayload Data RouteParams
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
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Placeholder - Blog.Slug_"
    , body = [ Html.text "You're on the page Blog.Slug_" ]
    }
