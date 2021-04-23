module Page.Hello.Name_ exposing (Data, Model, Msg, page)

import DataSource
import Document exposing (Document)
import Element
import Head
import Head.Seo as Seo
import Page exposing (Page, StaticPayload)
import Pages.ImagePath as ImagePath
import SiteOld


type alias Model =
    ()


type alias Msg =
    Never


type alias Route =
    { name : String
    }


page : Page Route ()
page =
    Page.noData
        { head = head
        , staticRoutes = DataSource.succeed [ { name = "world" } ]
        }
        |> Page.buildNoState { view = view }


head :
    StaticPayload () Route
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
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias Data =
    ()


view :
    StaticPayload Data Route
    -> Document msg
view static =
    { title = "TODO title"
    , body =
        [ Element.text <| "👋 " ++ static.routeParams.name
        ]
            |> Document.ElmUiView
    }
