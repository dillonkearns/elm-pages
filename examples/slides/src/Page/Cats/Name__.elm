module Page.Cats.Name__ exposing (Data, Model, Msg, page)

import DataSource
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Html.Styled exposing (text)
import Page exposing (Page, PageWithState, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { name : Maybe String }


page : Page RouteParams Data
page =
    Page.prerenderedRoute
        { head = head
        , routes = routes
        , data = data
        }
        |> Page.buildNoState { view = view }


routes : DataSource.DataSource (List RouteParams)
routes =
    DataSource.succeed
        [ { name = Just "larry"
          }
        , { name = Nothing
          }
        ]


data : RouteParams -> DataSource.DataSource Data
data routeParams =
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
    -> View Msg
view static =
    { body =
        [ text (static.routeParams.name |> Maybe.withDefault "NOTHING")
        ]
    , title = ""
    }
