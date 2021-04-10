module Template.Showcase exposing (Model, Msg, template)

import Element exposing (Element)
import Head
import Head.Seo as Seo
import Pages.ImagePath as ImagePath
import Pages.StaticHttp as StaticHttp
import Shared
import Showcase
import Template exposing (StaticPayload, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


template : TemplateWithState {} StaticData () Msg
template =
    Template.withStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed []
        , staticData = \_ -> staticData
        }
        |> Template.buildNoState { view = view }


staticData : StaticHttp.Request StaticData
staticData =
    Showcase.staticRequest



--(StaticHttp.get
--    (Secrets.succeed "file://elm.json")
--    OptimizedDecoder.string
--)


type alias DataFromFile =
    { body : List (Element Msg), title : String }


type alias StaticData =
    List Showcase.Entry


view :
    StaticPayload StaticData {}
    -> Shared.PageView Msg
view static =
    { title = "elm-pages blog"
    , body =
        let
            showcaseEntries =
                static.static
        in
        [ Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view showcaseEntries ]
            ]
        ]
    }


head : StaticPayload StaticData {} -> List Head.Tag
head staticPayload =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = ImagePath.build [ "images", "icon-png.png" ]
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "See some neat sites built using elm-pages! (Or submit yours!)"
        , locale = Nothing
        , title = "elm-pages sites showcase"
        }
        |> Seo.website
