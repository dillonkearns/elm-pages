module Template.Time exposing (Model, Msg, template)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import OptimizedDecoder
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Secrets
import Shared
import Site
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


type alias StaticData =
    String


template : Template {} StaticData
template =
    Template.withStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed []
        , staticData = staticData
        }
        |> Template.buildNoState { view = view }


staticData routeParams =
    StaticHttp.get (Secrets.succeed "http://worldtimeapi.org/api/timezone/America/Los_Angeles")
        (OptimizedDecoder.field "datetime" OptimizedDecoder.string)


head :
    StaticPayload StaticData {}
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
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    StaticPayload StaticData {}
    -> Shared.PageView msg
view static =
    { title = "TODO title"
    , body =
        [ Element.text static.static
        ]
    }
