module Page.Blog.Slug_ exposing (Data, Model, Msg, page, toRssItem)

import Article
import Cloudinary
import Data.Author as Author exposing (Author)
import DataSource
import DataSource.File as StaticFile
import DataSource.Glob as Glob
import Date exposing (Date)
import Document exposing (Document)
import Element exposing (Element)
import Element.Font as Font
import Element.Region
import Head
import Head.Seo as Seo
import MarkdownRenderer
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Palette
import Rss
import SiteOld
import StructuredData


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
    -> Document msg
view static =
    { title = static.data.frontmatter.title
    , body =
        let
            author =
                Author.dillon
        in
        [ Element.column [ Element.width Element.fill ]
            [ Element.column
                [ Element.padding 30
                , Element.spacing 40
                , Element.Region.mainContent
                , Element.width (Element.fill |> Element.maximum 800)
                , Element.centerX
                ]
                (Element.column [ Element.spacing 10 ]
                    [ Element.row [ Element.spacing 10 ]
                        [ Author.view [] author
                        , Element.column [ Element.spacing 10, Element.width Element.fill ]
                            [ Element.paragraph [ Font.bold, Font.size 24 ]
                                [ Element.text author.name
                                ]
                            , Element.paragraph [ Font.size 16 ]
                                [ Element.text author.bio
                                ]
                            ]
                        ]
                    ]
                    :: (publishedDateView static.data.frontmatter |> Element.el [ Font.size 16, Font.color (Element.rgba255 0 0 0 0.6) ])
                    :: Palette.blogHeading static.data.frontmatter.title
                    :: articleImageView static.data.frontmatter.image
                    :: static.data.body
                    |> List.map (Element.map never)
                )
            ]
        ]
            |> Document.ElmUiView
    }


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    let
        metadata =
            static.data.frontmatter
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


publishedDateView : { a | published : Date } -> Element msg
publishedDateView metadata =
    Element.text
        (metadata.published
            |> Date.format "MMMM ddd, yyyy"
        )


articleImageView : ImagePath -> Element msg
articleImageView articleImage =
    Element.image [ Element.width Element.fill ]
        { src = ImagePath.toString articleImage
        , description = "Article cover photo"
        }


type alias Data =
    { body : List (Element Msg)
    , frontmatter : ArticleMetadata
    }


data : RouteParams -> DataSource.DataSource Data
data route =
    StaticFile.request
        ("content/blog/" ++ route.slug ++ ".md")
        (OptimizedDecoder.map2 Data
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
        |> Glob.ignore (Glob.literal "content/blog/")
        |> Glob.ignore Glob.wildcard
        |> Glob.ignore (Glob.literal ".md")
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
