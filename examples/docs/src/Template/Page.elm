module Template.Page exposing (Model, Msg, template)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import SiteOld
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


type alias Route =
    {}


template : Template Route StaticData
template =
    Template.noStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed []
        }
        |> Template.buildNoState { view = view }


head :
    StaticPayload () Route
    -> List (Head.Tag Pages.PathKey)
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias StaticData =
    ()


view :
    StaticPayload StaticData Route
    -> Shared.PageView msg
view static =
    { title = "TODO title" -- metadata.title -- TODO
    , body =
        [ [ Element.column
                [ Element.padding 50
                , Element.spacing 60
                , Element.Region.mainContent
                ]
                []

          -- TODO render view with StaticHttp
          --(Tuple.second rendered |> List.map (Element.map never))
          ]
            |> Element.textColumn
                [ Element.width Element.fill
                ]
        ]
    }
