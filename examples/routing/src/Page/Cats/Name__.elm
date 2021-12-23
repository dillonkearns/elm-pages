module Page.Cats.Name__ exposing (Data, Model, Msg, page)

import DataSource
import Head
import Head.Seo as Seo
import Html.Styled exposing (text)
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    Never


type alias RouteParams =
    { name : Maybe String }


page : Page RouteParams Data
page =
    Page.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> Page.buildNoState { view = view }


pages : DataSource.DataSource (List RouteParams)
pages =
    DataSource.succeed
        [ { name = Just "larry"
          }
        , { name = Nothing
          }
        ]


data : RouteParams -> DataSource.DataSource Data
data routeParams =
    DataSource.succeed {}


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


type alias Data =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { body =
        [ text (static.routeParams.name |> Maybe.withDefault "NOTHING")
        ]
    , title = ""
    }
