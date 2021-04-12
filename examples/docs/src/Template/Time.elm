module Template.Time exposing (Model, Msg, template)

import Document exposing (Document)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Pages.ImagePath as ImagePath
import Pages.StaticHttp as StaticHttp
import Shared
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
    StaticHttp.succeed "TIME RESPONSE"



--StaticHttp.get (Secrets.succeed "http://worldtimeapi.org/api/timezone/America/Los_Angeles")
--    (OptimizedDecoder.field "datetime" OptimizedDecoder.string)


head :
    StaticPayload StaticData {}
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
    StaticPayload StaticData {}
    -> Document msg
view static =
    { title = "TODO title"
    , body =
        [ Element.text static.static
        ]
    }
