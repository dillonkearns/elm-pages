module Page.Time exposing (Model, Msg, StaticData, page)

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


type alias StaticData =
    String


page : Page {} StaticData
page =
    Page.withStaticData
        { head = head
        , staticRoutes = DataSource.succeed []
        , staticData = staticData
        }
        |> Page.buildNoState { view = view }


staticData routeParams =
    DataSource.succeed "TIME RESPONSE"



--StaticHttp.get (Secrets.succeed "http://worldtimeapi.org/api/timezone/America/Los_Angeles")
--    (OptimizedDecoder.field "datetime" OptimizedDecoder.string)


head :
    StaticPayload StaticData {}
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
    StaticPayload StaticData {}
    -> Document msg
view static =
    { title = "TODO title"
    , body =
        [ Element.text static.static
        ]
            |> Document.ElmUiView
    }
