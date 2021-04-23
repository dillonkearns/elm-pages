module Page.Slide exposing (Model, Msg, StaticData, template)

import Element exposing (Element)
import Document exposing (Document)
import Pages.ImagePath as ImagePath
import Head
import Head.Seo as Seo
import DataSource
import Shared
import Page exposing (StaticPayload, Page, PageWithState)


type alias Model =
    ()


type alias Msg =
    Never

type alias RouteParams =
    {  }

template : Page RouteParams StaticData
template =
    Page.noStaticData
        { head = head
        , staticRoutes = DataSource.succeed [{}]
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

