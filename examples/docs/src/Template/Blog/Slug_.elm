module Template.Blog.Slug_ exposing (Model, Msg, articlesRequest, routes, template, toRssItem)

import Cloudinary
import Data.Author as Author exposing (Author)
import Date exposing (Date)
import Element exposing (Element)
import Element.Font as Font
import Element.Region
import Glob
import Head
import Head.Seo as Seo
import List.Extra
import MarkdownRenderer
import OptimizedDecoder
import Pages
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticFile as StaticFile
import Pages.StaticHttp as StaticHttp
import Palette
import Rss
import Shared
import SiteOld
import StructuredData
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


type alias Route =
    { slug : String }


routes : StaticHttp.Request (List Route)
routes =
    Glob.succeed Route
        |> Glob.drop (Glob.literal "content/blog/")
        |> Glob.keep Glob.wildcard
        |> Glob.drop (Glob.literal ".md")
        |> Glob.toStaticHttp


type alias BlogPost =
    { title : String
    , description : String
    , published : Date
    , author : Author
    , image : ImagePath Pages.PathKey
    , draft : Bool
    }


template : Template Route DataFromFile
template =
    Template.withStaticData
        { staticData = staticData
        , head = head
        , staticRoutes = routes

        --, route = route
        }
        |> Template.buildNoState { view = view }


findMatchingImage : String -> Maybe (ImagePath Pages.PathKey)
findMatchingImage imageAssetPath =
    List.Extra.find (\image -> ImagePath.toString image == imageAssetPath) Pages.allImages


view :
    StaticPayload DataFromFile Route
    -> Shared.PageView msg
view { static } =
    { title = static.frontmatter.title
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
                    :: (publishedDateView static.frontmatter |> Element.el [ Font.size 16, Font.color (Element.rgba255 0 0 0 0.6) ])
                    :: Palette.blogHeading static.frontmatter.title
                    :: articleImageView static.frontmatter.image
                    :: static.body
                    |> List.map (Element.map never)
                )
            ]
        ]
    }


head :
    StaticPayload DataFromFile Route
    -> List (Head.Tag Pages.PathKey)
head { path, static } =
    let
        metadata =
            static.frontmatter
    in
    Head.structuredData
        (StructuredData.article
            { title = metadata.title
            , description = metadata.description
            , author = StructuredData.person { name = Author.dillon.name }
            , publisher = StructuredData.person { name = Author.dillon.name }
            , url = SiteOld.canonicalUrl ++ "/" ++ PagePath.toString path
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


publishedDateView : { a | published : Date.Date } -> Element msg
publishedDateView metadata =
    Element.text
        (metadata.published
            |> Date.format "MMMM ddd, yyyy"
        )


articleImageView : ImagePath Pages.PathKey -> Element msg
articleImageView articleImage =
    Element.image [ Element.width Element.fill ]
        { src = ImagePath.toString articleImage
        , description = "Article cover photo"
        }


type alias DataFromFile =
    { body : List (Element Msg)
    , frontmatter : ArticleMetadata
    }


staticData : Route -> StaticHttp.Request DataFromFile
staticData route =
    StaticFile.request
        --"content/blog/extensible-markdown-parsing-in-elm.md"
        ("content/blog/" ++ route.slug ++ ".md")
        (OptimizedDecoder.map2 DataFromFile
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


articlesRequest : StaticHttp.Request (List ArticleMetadata)
articlesRequest =
    Glob.succeed identity
        |> Glob.keep Glob.fullFilePath
        |> Glob.drop (Glob.literal "content/blog/")
        |> Glob.drop Glob.wildcard
        |> Glob.drop (Glob.literal ".md")
        |> Glob.toStaticHttp
        |> StaticHttp.andThen
            (\articleFilePaths ->
                articleFilePaths
                    |> List.filter (\filePath -> filePath |> String.contains "index" |> not)
                    |> List.map
                        (\articleFilePath ->
                            StaticFile.request articleFilePath
                                (StaticFile.frontmatter frontmatterDecoder)
                        )
                    |> StaticHttp.combine
            )
