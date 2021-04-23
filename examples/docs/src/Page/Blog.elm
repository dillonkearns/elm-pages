module Page.Blog exposing (Data, Model, Msg, page)

import Article
import DataSource
import Document exposing (Document)
import Element
import Head
import Head.Seo as Seo
import Index
import Page exposing (DynamicContext, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath
import Pages.PagePath exposing (PagePath)
import Shared
import SiteOld


type Msg
    = Msg


page : PageWithState RouteParams Data Model Msg
page =
    Page.withData
        { head = head
        , data = \_ -> data
        , staticRoutes = DataSource.succeed []
        }
        |> Page.buildWithLocalState
            { view = view
            , init = init
            , update = update
            , subscriptions = \_ _ _ -> Sub.none
            }


data : DataSource.DataSource Data
data =
    Article.allMetadata


type alias Data =
    List ( PagePath, Article.ArticleMetadata )


init :
    StaticPayload Data RouteParams
    -> ( Model, Cmd Msg )
init _ =
    ( Model, Cmd.none )


type alias RouteParams =
    {}


update :
    DynamicContext Shared.Model
    -> StaticPayload Data RouteParams
    -> Msg
    -> Model
    -> ( Model, Cmd Msg )
update dynamic static msg model =
    ( model, Cmd.none )


type alias Model =
    {}


view :
    Model
    -> Shared.Model
    -> StaticPayload Data {}
    -> Document Msg
view thing model staticPayload =
    { title = "elm-pages blog"
    , body =
        [ Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ]
                [ --Element.text
                  --    (staticPayload.static
                  --        |> String.join ", "
                  --    )
                  Index.view staticPayload.static
                ]
            ]
        ]
            |> Document.ElmUiView
    }


head : StaticPayload Data {} -> List Head.Tag
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
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "elm-pages blog"
        }
        |> Seo.website



--fileRequest : StaticHttp.Request DataFromFile
--fileRequest =
--    StaticFile.request
--        "content/blog/extensible-markdown-parsing-in-elm.md"
--        (OptimizedDecoder.map2 DataFromFile
--            (StaticFile.body
--                |> OptimizedDecoder.andThen
--                    (\rawBody ->
--                        case rawBody |> MarkdownRenderer.view |> Result.map Tuple.second of
--                            Ok renderedBody ->
--                                OptimizedDecoder.succeed renderedBody
--
--                            Err error ->
--                                OptimizedDecoder.fail error
--                    )
--            )
--            (StaticFile.frontmatter frontmatterDecoder)
--        )
