module Page.Time exposing (Data, Model, Msg, page)

import DataSource
import DataSource.Http
import Document exposing (Document)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath
import Secrets
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
    Page.serverlessRoute
        { head = head
        , data = \_ _ -> data
        , routeFound = \_ -> DataSource.succeed True
        }
        |> Page.buildNoState { view = view }


data : DataSource.DataSource String
data =
    DataSource.Http.get (Secrets.succeed "http://localhost:3000/.netlify/functions/time")
        OptimizedDecoder.string


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
