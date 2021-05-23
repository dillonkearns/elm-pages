module Page.Time exposing (Data, Model, Msg, page)

import DataSource
import DataSource.Http
import Head
import Head.Seo as Seo
import Html.Styled as Html
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.Url
import Path
import Secrets
import Shared
import View exposing (View)


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
    DataSource.Http.get (Secrets.succeed "/.netlify/functions/time")
        OptimizedDecoder.string


head :
    StaticPayload Data {}
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = [ "images", "icon-png.png" ] |> Path.join |> Pages.Url.fromPath
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
    -> View msg
view static =
    { title = "TODO title"
    , body =
        [ Html.text static.data
        ]
    }
