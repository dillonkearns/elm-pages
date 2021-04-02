module Template.Page exposing (Model, Msg, template)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Shared
import Site
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


template : Template {} ()
template =
    Template.noStaticData { head = head }
        |> Template.buildNoState { view = view }


head :
    StaticPayload ()
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
        , description = Site.tagline
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias StaticData =
    ()


view :
    StaticPayload StaticData
    -> Shared.RenderedBody
    -> Shared.PageView msg
view static rendered =
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
