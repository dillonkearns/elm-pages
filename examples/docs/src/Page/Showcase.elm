module Page.Showcase exposing (Model, Msg, StaticData, page)

import DataSource
import Document exposing (Document)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Page exposing (PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath
import Shared
import Showcase


type alias Model =
    ()


type alias Msg =
    Never


page : PageWithState {} StaticData () Msg
page =
    Page.withStaticData
        { head = head
        , staticRoutes = DataSource.succeed []
        , staticData = \_ -> staticData
        }
        |> Page.buildNoState { view = view }


staticData : DataSource.DataSource StaticData
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
    -> Document Msg
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
            |> Document.ElmUiView
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
