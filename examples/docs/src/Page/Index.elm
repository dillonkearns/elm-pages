module Page.Index exposing (Data, Model, Msg, page)

import DataSource
import DataSource.File as StaticFile
import Document exposing (Document)
import Element
import Element.Region
import Head
import Head.Seo as Seo
import MarkdownRenderer
import OptimizedDecoder
import Page exposing (Page, StaticPayload)
import Pages.ImagePath as ImagePath
import Shared
import SiteOld


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    {}


type alias Data =
    List (Element.Element Msg)


page : Page RouteParams Data
page =
    Page.singleRoute
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


head :
    StaticPayload Data RouteParams
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
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    { title = "elm-pages - a statically typed site generator" -- metadata.title -- TODO
    , body =
        [ [ Element.column
                [ Element.padding 50
                , Element.spacing 60
                , Element.Region.mainContent
                ]
                static.data
          ]
            |> Element.textColumn
                [ Element.width Element.fill
                ]
        ]
            |> Document.ElmUiView
    }


data : DataSource.DataSource (List (Element.Element msg))
data =
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
