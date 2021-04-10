module Template.Hello.Name_ exposing (Model, Msg, template)

import Element
import Head
import Head.Seo as Seo
import Pages.ImagePath as ImagePath
import Pages.StaticHttp as StaticHttp
import Shared
import SiteOld
import Template exposing (StaticPayload, Template)


type alias Model =
    ()


type alias Msg =
    Never


type alias Route =
    { name : String
    }


template : Template Route ()
template =
    Template.noStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed [ { name = "world" } ]
        }
        |> Template.buildNoState { view = view }


head :
    StaticPayload () Route
    -> List (Head.Tag ())
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


type alias StaticData =
    ()


view :
    StaticPayload StaticData Route
    -> Shared.PageView msg
view static =
    { title = "TODO title"
    , body =
        [ Element.text <| "👋 " ++ static.routeParams.name
        ]
    }
