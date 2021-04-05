module Template.Blog exposing (Model, Msg, template)

import Article
import Cloudinary
import Date exposing (Date)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Index
import OptimizedDecoder
import Pages exposing (images)
import Pages.ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticFile as StaticFile
import Pages.StaticHttp as StaticHttp
import Shared
import Showcase
import Site
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
    List ( PagePath Pages.PathKey, Article.ArticleMetadata )


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
    -> StaticPayload StaticData
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


head : StaticPayload StaticData -> List (Head.Tag Pages.PathKey)
head staticPayload =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = Site.tagline
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


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , image : ImagePath Pages.PathKey
    , draft : Bool
    }


frontmatterDecoder : OptimizedDecoder.Decoder ArticleMetadata
frontmatterDecoder =
    OptimizedDecoder.map5 ArticleMetadata
        (OptimizedDecoder.field "title" OptimizedDecoder.string)
        (OptimizedDecoder.field "description" OptimizedDecoder.string)
        (OptimizedDecoder.field "published"
            (OptimizedDecoder.string
                |> OptimizedDecoder.andThen
                    (\isoString ->
                        case Date.fromIsoString isoString of
                            Ok date ->
                                OptimizedDecoder.succeed date

                            Err error ->
                                OptimizedDecoder.fail error
                    )
            )
        )
        (OptimizedDecoder.field "image" imageDecoder)
        (OptimizedDecoder.field "draft" OptimizedDecoder.bool
            |> OptimizedDecoder.maybe
            |> OptimizedDecoder.map (Maybe.withDefault False)
        )


imageDecoder : OptimizedDecoder.Decoder (ImagePath Pages.PathKey)
imageDecoder =
    OptimizedDecoder.string
        |> OptimizedDecoder.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)
