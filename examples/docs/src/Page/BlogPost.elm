module Page.BlogPost exposing (Model, Msg, template)

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
import Shared
import SiteOld
import StructuredData
import Template exposing (StaticPayload, Template, TemplateWithState)
import TemplateMetadata exposing (BlogPost)


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


template : Template BlogPost DataFromFile
template =
    Template.withStaticData
        { staticData = fileRequest
        , head = head

        --, route = route
        }
        |> Template.buildNoState { view = view }


findMatchingImage : String -> Maybe (ImagePath Pages.PathKey)
findMatchingImage imageAssetPath =
    List.Extra.find (\image -> ImagePath.toString image == imageAssetPath) Pages.allImages


view :
    StaticPayload DataFromFile
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
                    :: []
                    |> List.map (Element.map never)
                )
            ]
        ]
    }


head :
    StaticPayload DataFromFile
    -> List (Head.Tag Pages.PathKey)
head { path, static } =
    Head.structuredData
        (StructuredData.article
            { title = static.frontmatter.title
            , description = static.frontmatter.description
            , author = StructuredData.person { name = Author.dillon.name }
            , publisher = StructuredData.person { name = Author.dillon.name }
            , url = SiteOld.canonicalUrl ++ "/" ++ PagePath.toString path
            , imageUrl = SiteOld.canonicalUrl ++ "/" ++ ImagePath.toString static.frontmatter.image
            , datePublished = Date.toIsoString static.frontmatter.published
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
                    { url = static.frontmatter.image
                    , alt = static.frontmatter.description
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = static.frontmatter.description
                , locale = Nothing
                , title = static.frontmatter.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Just (Date.toIsoString static.frontmatter.published)
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


fileRequest : StaticHttp.Request DataFromFile
fileRequest =
    StaticFile.request
        "content/blog/extensible-markdown-parsing-in-elm.md"
        --"content/blog/" ++ route.slug ++ ".md"
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
