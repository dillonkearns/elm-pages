module Page.Time exposing (Data, Model, Msg, page)

import DataSource
import Document exposing (Document)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath
import Shared


type alias Model =
    ()


type alias Msg =
    Never


type alias Data =
    String


type alias RouteParams =
    {}


page : Page RouteParams Data
page =
    Page.withData
        { head = head
        , staticRoutes = DataSource.succeed []
        , data = data
        }
        |> Page.buildNoState { view = view }


data : RouteParams -> DataSource.DataSource String
data routeParams =
    DataSource.succeed "TIME RESPONSE"



--StaticHttp.get (Secrets.succeed "http://worldtimeapi.org/api/timezone/America/Los_Angeles")
--    (OptimizedDecoder.field "datetime" OptimizedDecoder.string)


head :
    StaticPayload Data {}
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = ImagePath.build [ "images", "icon-png.png" ]
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
    StaticPayload Data {}
    -> Document msg
view static =
    { title = "TODO title"
    , body =
        [ Element.text static.static
        ]
            |> Document.ElmUiView
    }
