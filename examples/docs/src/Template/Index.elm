module Template.Index exposing (Model, Msg, StaticData, template)

import DataSource
import Document exposing (Document)
import Element
import Element.Region
import Head
import Head.Seo as Seo
import MarkdownRenderer
import OptimizedDecoder
import Pages.ImagePath as ImagePath
import Pages.StaticFile as StaticFile
import Shared
import SiteOld
import Template exposing (StaticPayload, Template)


type alias Model =
    ()


type alias Msg =
    Never


type alias Route =
    {}


type alias StaticData =
    List (Element.Element Msg)


template : Template Route StaticData
template =
    Template.withStaticData
        { head = head
        , staticRoutes = DataSource.succeed []
        , staticData = staticData
        }
        |> Template.buildNoState { view = view }


head :
    StaticPayload StaticData Route
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
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    StaticPayload StaticData Route
    -> Document Msg
view static =
    { title = "elm-pages - a statically typed site generator" -- metadata.title -- TODO
    , body =
        [ [ Element.column
                [ Element.padding 50
                , Element.spacing 60
                , Element.Region.mainContent
                ]
                static.static
          ]
            |> Element.textColumn
                [ Element.width Element.fill
                ]
        ]
    }


staticData : Route -> DataSource.Request (List (Element.Element msg))
staticData route =
    StaticFile.request
        "content/index.md"
        (StaticFile.body
            |> OptimizedDecoder.andThen
                (\rawBody ->
                    case rawBody |> MarkdownRenderer.view |> Result.map Tuple.second of
                        Ok renderedBody ->
                            OptimizedDecoder.succeed renderedBody

                        Err error ->
                            OptimizedDecoder.fail error
                )
        )
