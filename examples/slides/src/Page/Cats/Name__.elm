module Page.Cats.Name__ exposing (Data, Model, Msg, page)

import BackendTask
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Html.Styled exposing (text)
import RouteBuilder exposing (StatelessRoute, StatefulRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { name : Maybe String }


page : StatelessRoute RouteParams Data ActionData
page =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask.BackendTask (List RouteParams)
pages =
    BackendTask.succeed
        [ { name = Just "larry"
          }
        , { name = Nothing
          }
        ]


data : RouteParams -> BackendTask.BackendTask Data
data routeParams =
    BackendTask.succeed ()


head :
    StaticPayload Data ActionData RouteParams
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
    StaticPayload Data ActionData RouteParams
    -> View Msg
view static =
    { body =
        [ text (static.routeParams.name |> Maybe.withDefault "NOTHING")
        ]
    , title = ""
    }
