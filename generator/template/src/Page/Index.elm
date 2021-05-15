module Page.Index exposing (Model, Msg, Data, page)

import Element exposing (Element)
import Document exposing (Document)
import Pages.ImagePath as ImagePath
import Head
import Head.Seo as Seo
import DataSource exposing (DataSource)
import Shared
import Page exposing (StaticPayload, Page, PageWithState)


type alias Model =
    ()


type alias Msg =
    Never

type alias RouteParams =
    {}

page : Page RouteParams Data
page =
    Page.singleRoute
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()



head :
    StaticPayload Data RouteParams
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
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    Document.placeholder "Index"
