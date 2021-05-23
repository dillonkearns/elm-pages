module Page.Blog.Slug_ exposing (Data, Model, Msg, page, toRssItem)

import Article
import Cloudinary
import Css
import Data.Author as Author exposing (Author)
import DataSource
import DataSource.File as StaticFile
import DataSource.Glob as Glob
import Date exposing (Date)
import Head
import Head.Seo as Seo
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Markdown.Parser
import Markdown.Renderer
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Rss
import SiteOld
import StructuredData
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import TailwindMarkdownRenderer
import View exposing (View)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { slug : String }


type alias BlogPost =
    { title : String
    , description : String
    , published : Date
    , author : Author
    , image : ImagePath
    , draft : Bool
    }


page : Page RouteParams Data
page =
    Page.prerenderedRoute
        { data = data
        , head = head
        , routes = routes
        }
        |> Page.buildNoState { view = view }


routes : DataSource.DataSource (List RouteParams)
routes =
    Article.blogPostsGlob
        |> DataSource.map
            (List.map
                (\globData ->
                    { slug = globData.slug }
                )
            )


view :
    StaticPayload Data RouteParams
    -> View Msg
view static =
    { title = static.data.metadata.title
    , body =
        let
            author =
                Author.dillon
        in
        [ div
            [ css
                [ Tw.min_h_screen
                , Tw.w_full
                , Tw.relative
                ]
            ]
            [ div
                [ css
                    [ Tw.pt_32
                    , Tw.pb_16
                    , Tw.px_8
                    , Tw.flex
                    , Tw.flex_col
                    ]
                ]
                [ div
                    [ css
                        [ Bp.md [ Tw.mx_auto ]
                        ]
                    ]
                    [ h1
                        [ css
                            [ Tw.text_center
                            , Tw.text_4xl
                            , Tw.font_bold
                            , Tw.tracking_tight
                            , Tw.mt_2
                            , Tw.mb_8
                            ]
                        ]
                        [ text static.data.metadata.title
                        ]
                    , authorView author static.data
                    , div
                        [ css
                            [ Tw.prose
                            ]
                        ]
                        static.data.body
                    ]
                ]
            ]
        ]
    }


authorView : Author -> Data -> Html msg
authorView author static =
    div
        [ css
            [ Tw.flex
            , Tw.mb_16

            --, Tw.flex_shrink_0
            ]
        ]
        [ img
            [ Attr.src (author.avatar |> ImagePath.toString)
            , css
                [ Tw.rounded_full
                , Tw.h_10
                , Tw.w_10
                ]
            ]
            []
        , div
            [ css [ Tw.ml_3 ]
            ]
            [ div
                [ css
                    []
                ]
                [ p
                    [ css
                        [ Tw.text_sm
                        , Tw.font_medium
                        , Tw.text_gray_900
                        ]
                    ]
                    [ span
                        []
                        [ text author.name ]
                    ]
                ]
            , div
                [ css
                    [ Tw.flex
                    , Tw.space_x_1
                    , Tw.text_sm
                    , Tw.text_gray_500
                    , Tw.text_gray_400
                    ]
                ]
                [ time
                    [ Attr.datetime "2020-03-16"
                    ]
                    [ text (static.metadata.published |> Date.format "MMMM ddd, yyyy") ]
                ]
            ]
        ]


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    let
        metadata =
            static.data.metadata
    in
    Head.structuredData
        (StructuredData.article
            { title = metadata.title
            , description = metadata.description
            , author = StructuredData.person { name = Author.dillon.name }
            , publisher = StructuredData.person { name = Author.dillon.name }
            , url = SiteOld.canonicalUrl ++ "/" ++ PagePath.toString static.path
            , imageUrl = SiteOld.canonicalUrl ++ "/" ++ ImagePath.toString metadata.image
            , datePublished = Date.toIsoString metadata.published
            , mainEntityOfPage =
                StructuredData.softwareSourceCode
                    { codeRepositoryUrl = "https://github.com/dillonkearns/elm-pages"
                    , description = "A statically typed site generator for Elm."
                    , author = "Dillon Kearns"
                    , programmingLanguage = StructuredData.elmLang
                    }
            }
        )
        :: (Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = metadata.image
                    , alt = metadata.description
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = metadata.description
                , locale = Nothing
                , title = metadata.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Just (Date.toIsoString metadata.published)
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }
           )


type alias Data =
    { body : List (Html Msg)
    , metadata : ArticleMetadata
    }


data : RouteParams -> DataSource.DataSource Data
data route =
    StaticFile.request
        ("content/blog/" ++ route.slug ++ ".md")
        (OptimizedDecoder.map2 Data
            (StaticFile.body
                |> OptimizedDecoder.andThen
                    (\rawBody ->
                        rawBody
                            |> Markdown.Parser.parse
                            |> Result.mapError (\_ -> "Couldn't parse markdown.")
                            |> Result.andThen (Markdown.Renderer.render TailwindMarkdownRenderer.renderer)
                            --|> Result.map Tuple.second
                            |> OptimizedDecoder.fromResult
                    )
            )
            (StaticFile.frontmatter frontmatterDecoder)
        )


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , image : ImagePath
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
                        Date.fromIsoString isoString
                            |> OptimizedDecoder.fromResult
                    )
            )
        )
        (OptimizedDecoder.field "image" imageDecoder)
        (OptimizedDecoder.field "draft" OptimizedDecoder.bool
            |> OptimizedDecoder.maybe
            |> OptimizedDecoder.map (Maybe.withDefault False)
        )


imageDecoder : OptimizedDecoder.Decoder ImagePath
imageDecoder =
    OptimizedDecoder.string
        |> OptimizedDecoder.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)


toRssItem :
    ArticleMetadata
    -> Maybe Rss.Item
toRssItem article =
    if article.draft then
        Nothing

    else
        Just
            { title = article.title
            , description = article.description
            , url = "TODO" --PagePath.toString page.path
            , categories = []
            , author = Author.dillon.name
            , pubDate = Rss.Date article.published
            , content = Nothing
            }


articlesRequest : DataSource.DataSource (List ArticleMetadata)
articlesRequest =
    Glob.succeed identity
        |> Glob.capture Glob.fullFilePath
        |> Glob.match (Glob.literal "content/blog/")
        |> Glob.match Glob.wildcard
        |> Glob.match (Glob.literal ".md")
        |> Glob.toDataSource
        |> DataSource.andThen
            (\articleFilePaths ->
                articleFilePaths
                    |> List.filter (\filePath -> filePath |> String.contains "index" |> not)
                    |> List.map
                        (\articleFilePath ->
                            StaticFile.request articleFilePath
                                (StaticFile.frontmatter frontmatterDecoder)
                        )
                    |> DataSource.combine
            )
