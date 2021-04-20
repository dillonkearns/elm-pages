module Template.Blog exposing (Model, Msg, StaticData, template)

import Article
import Browser.Navigation
import DataSource
import Document exposing (Document)
import Element
import Head
import Head.Seo as Seo
import Index
import Pages.ImagePath as ImagePath
import Pages.PagePath exposing (PagePath)
import Shared
import SiteOld
import Template exposing (DynamicContext, StaticPayload, TemplateWithState)


type Msg
    = Msg


template : TemplateWithState {} StaticData Model Msg
template =
    Template.withStaticData
        { head = head
        , staticData = \_ -> staticData
        , staticRoutes = DataSource.succeed []
        }
        |> Template.buildWithLocalState
            { view = view
            , init = init
            , update = update

            --\_ _ _ model -> ( model, Cmd.none )
            , subscriptions = \_ _ _ -> Sub.none
            }


staticData : DataSource.Request StaticData
staticData =
    --StaticFile.glob "content/blog/*.md"
    Article.allMetadata


type alias StaticData =
    List ( PagePath, Article.ArticleMetadata )


init : {} -> ( Model, Cmd Msg )
init _ =
    ( Model, Cmd.none )


type alias RouteParams =
    {}


update :
    DynamicContext Shared.Model
    -> StaticData
    -> RouteParams
    -> Msg
    -> Model
    -> ( Model, Cmd Msg )
update dynamic sharedModel routeParams msg model =
    ( model, Cmd.none )


type alias Model =
    {}


view :
    Model
    -> Shared.Model
    -> StaticPayload StaticData {}
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
