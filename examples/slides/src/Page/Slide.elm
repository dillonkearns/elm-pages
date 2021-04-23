module Page.Slide exposing (Model, Msg, StaticData, page)

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


type alias RouteParams =
    {}


page : Page RouteParams StaticData
page =
    Page.noStaticData
        { head = head
        , staticRoutes = DataSource.succeed [ {} ]
        }
        |> Page.buildNoState { view = view }


head :
    StaticPayload StaticData RouteParams
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


type alias StaticData =
    ()


view :
    StaticPayload StaticData RouteParams
    -> Document Msg
view static =
    { title = "TODO title"
    , body = []
    }
