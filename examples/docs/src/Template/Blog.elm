module Template.Blog exposing (Model, Msg, template)

import Article
import Element
import Head
import Head.Seo as Seo
import Index
import Pages.ImagePath as ImagePath
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import SiteOld
import Template exposing (StaticPayload, TemplateWithState)


type Msg
    = Msg


template : TemplateWithState {} StaticData Model Msg
template =
    Template.withStaticData
        { head = head
        , staticData = \_ -> staticData
        , staticRoutes = StaticHttp.succeed []
        }
        |> Template.buildWithLocalState
            { view = view
            , init = init
            , update = update

            --\_ _ _ model -> ( model, Cmd.none )
            , subscriptions = \_ _ _ -> Sub.none
            }


staticData : StaticHttp.Request StaticData
staticData =
    --StaticFile.glob "content/blog/*.md"
    Article.allMetadata


type alias StaticData =
    List ( PagePath, Article.ArticleMetadata )


init : {} -> ( Model, Cmd Msg )
init _ =
    ( Model, Cmd.none )


update :
    Shared.Model
    -> {}
    -> Msg
    -> Model
    -> ( Model, Cmd Msg )
update sharedModel metadata msg model =
    ( model, Cmd.none )


type alias Model =
    {}


view :
    Model
    -> Shared.Model
    -> StaticPayload StaticData {}
    -> Shared.PageView Msg
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


head : StaticPayload StaticData {} -> List (Head.Tag ())
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
