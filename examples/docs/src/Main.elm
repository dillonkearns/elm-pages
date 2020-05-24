module Main exposing (main)

import AllMetadata
import Color
import Data.Author as Author
import Date
import DocSidebar
import DocumentSvg
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Events
import Element.Font as Font
import Element.Region
import FontAwesome
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Index
import Json.Decode as Decode exposing (Decoder)
import Json.Encode
import MarkdownRenderer
import Metadata exposing (Metadata)
import MetadataNew
import MySitemap
import OptimizedDecoder as D
import Pages exposing (images, pages)
import Pages.Directory as Directory exposing (Directory)
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Page)
import Pages.StaticHttp as StaticHttp
import Palette
import Rss
import RssPlugin
import Secrets
import Showcase
import SiteConfig
import StructuredData
import Template.BlogPost
import Template.Showcase
import TemplateDemultiplexer


manifest : Manifest.Config Pages.PathKey
manifest =
    { backgroundColor = Just Color.white
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Just Color.white
    , startUrl = pages.blog.staticHttp
    , shortName = Just "elm-pages"
    , sourceIcon = images.iconPng
    }


type alias View =
    ( MarkdownRenderer.TableOfContents, List (Element Msg) )


main : Pages.Platform.Program TemplateDemultiplexer.Model TemplateDemultiplexer.Msg AllMetadata.Metadata TemplateDemultiplexer.View
main =
    TemplateDemultiplexer.mainTemplate
        { documents =
            [ { extension = "md"
              , metadata = MetadataNew.decoder
              , body = MarkdownRenderer.view
              }
            ]
        , manifest = SiteConfig.manifest
        , canonicalSiteUrl = SiteConfig.canonicalUrl
        }



--main : Pages.Platform.Program Model Msg Metadata View
--main =
--    Pages.Platform.init
--        { init = init
--        , view = view
--        , update = update
--        , subscriptions = subscriptions
--        , documents =
--            [ { extension = "md"
--              , metadata = Metadata.decoder
--              , body = MarkdownRenderer.view
--              }
--            ]
--        , onPageChange = Just OnPageChange
--        , manifest = manifest
--        , canonicalSiteUrl = canonicalSiteUrl
--        , internals = Pages.internals
--        }
--        |> RssPlugin.generate
--            { siteTagline = siteTagline
--            , siteUrl = canonicalSiteUrl
--            , title = "elm-pages Blog"
--            , builtAt = Pages.builtAt
--            , indexPage = Pages.pages.blog.index
--            }
--            metadataToRssItem
--        |> MySitemap.install { siteUrl = canonicalSiteUrl } metadataToSitemapEntry
--        |> Pages.Platform.toProgram


metadataToRssItem :
    { path : PagePath Pages.PathKey
    , frontmatter : Metadata
    , body : String
    }
    -> Maybe Rss.Item
metadataToRssItem page =
    case page.frontmatter of
        Metadata.Article article ->
            if article.draft then
                Nothing

            else
                Just
                    { title = article.title
                    , description = article.description
                    , url = PagePath.toString page.path
                    , categories = []
                    , author = article.author.name
                    , pubDate = Rss.Date article.published
                    , content = Nothing
                    }

        _ ->
            Nothing


metadataToSitemapEntry :
    List
        { path : PagePath Pages.PathKey
        , frontmatter : Metadata
        , body : String
        }
    -> List { path : String, lastMod : Maybe String }
metadataToSitemapEntry siteMetadata =
    siteMetadata
        |> List.filter
            (\page ->
                case page.frontmatter of
                    Metadata.Article articleData ->
                        not articleData.draft

                    _ ->
                        True
            )
        |> List.map
            (\page ->
                { path = PagePath.toString page.path, lastMod = Nothing }
            )


type alias Model =
    { showMobileMenu : Bool
    }


init :
    Maybe
        { path : PagePath Pages.PathKey
        , query : Maybe String
        , fragment : Maybe String
        }
    -> ( Model, Cmd Msg )
init maybePagePath =
    ( Model False, Cmd.none )


type Msg
    = OnPageChange
        { path : PagePath Pages.PathKey
        , query : Maybe String
        , fragment : Maybe String
        }
    | ToggleMobileMenu


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnPageChange page ->
            ( { model | showMobileMenu = False }, Cmd.none )

        ToggleMobileMenu ->
            ( { model | showMobileMenu = not model.showMobileMenu }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


pageView :
    Int
    -> Model
    -> List ( PagePath Pages.PathKey, Metadata )
    -> { path : PagePath Pages.PathKey, frontmatter : Metadata }
    -> ( MarkdownRenderer.TableOfContents, List (Element Msg) )
    -> { title : String, body : Element Msg }
pageView stars model siteMetadata page viewForPage =
    case page.frontmatter of
        Metadata.Doc metadata ->
            { title = metadata.title
            , body =
                [ Element.row []
                    [ DocSidebar.view page.path siteMetadata
                        |> Element.el [ Element.width (Element.fillPortion 2), Element.alignTop, Element.height Element.fill ]
                    , Element.column [ Element.width (Element.fillPortion 8), Element.padding 35, Element.spacing 15 ]
                        [ Palette.heading 1 [ Element.text metadata.title ]
                        , Element.column [ Element.spacing 20 ]
                            [ tocView (Tuple.first viewForPage)
                            , Element.column
                                [ Element.padding 50
                                , Element.spacing 30
                                , Element.Region.mainContent
                                ]
                                (Tuple.second viewForPage)
                            ]
                        ]
                    ]
                ]
                    |> Element.textColumn
                        [ Element.width Element.fill
                        , Element.height Element.fill
                        ]
            }

        _ ->
            Debug.todo ""


logoLink =
    Element.link []
        { url = "/"
        , label =
            Element.row
                [ Font.size 30
                , Element.spacing 16
                , Element.htmlAttribute (Attr.class "navbar-title")
                ]
                [ DocumentSvg.view
                , Element.text "elm-pages"
                ]
        }


logoLinkMobile =
    Element.link []
        { url = "/"
        , label =
            Element.row
                [ Font.size 30
                , Element.spacing 16
                , Element.htmlAttribute (Attr.class "navbar-title")
                ]
                [ Element.text "elm-pages"
                ]
        }


navbarLinks stars currentPath =
    [ elmDocsLink
    , githubRepoLink stars

    --, highlightableLink currentPath pages.docs.directory "Docs"
    --, highlightableLink currentPath pages.showcase.directory "Showcase"
    --, highlightableLink currentPath pages.blog.directory "Blog"
    ]


responsiveHeader =
    Element.row
        [ Element.width Element.fill
        , Element.spaceEvenly
        , Element.htmlAttribute (Attr.class "responsive-mobile")
        , Element.width Element.fill
        , Element.padding 20
        ]
        [ logoLinkMobile
        , FontAwesome.icon "fas fa-bars" |> Element.el [ Element.alignRight, Element.Events.onClick ToggleMobileMenu ]
        ]


highlightableLink :
    PagePath Pages.PathKey
    -> Directory Pages.PathKey Directory.WithIndex
    -> String
    -> Element msg
highlightableLink currentPath linkDirectory displayName =
    let
        isHighlighted =
            currentPath |> Directory.includes linkDirectory
    in
    Element.link
        (if isHighlighted then
            [ Font.underline
            , Font.color Palette.color.primary
            ]

         else
            []
        )
        { url = linkDirectory |> Directory.indexPath |> PagePath.toString
        , label = Element.text displayName
        }


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/abouts-cards>
<https://htmlhead.dev>
<https://html.spec.whatwg.org/multipage/semantics.html#standard-metadata-names>
<https://ogp.me/>
-}
head : PagePath Pages.PathKey -> Metadata -> List (Head.Tag Pages.PathKey)
head currentPath metadata =
    case metadata of
        Metadata.Page meta ->
            Seo.summary
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.iconPng
                    , alt = "elm-pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = meta.title
                }
                |> Seo.website

        Metadata.Doc meta ->
            Seo.summary
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.iconPng
                    , alt = "elm pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , locale = Nothing
                , description = siteTagline
                , title = meta.title
                }
                |> Seo.website

        Metadata.Article meta ->
            Head.structuredData
                (StructuredData.article
                    { title = meta.title
                    , description = meta.description
                    , author = StructuredData.person { name = meta.author.name }
                    , publisher = StructuredData.person { name = "Dillon Kearns" }
                    , url = canonicalSiteUrl ++ "/" ++ PagePath.toString currentPath
                    , imageUrl = canonicalSiteUrl ++ "/" ++ ImagePath.toString meta.image
                    , datePublished = Date.toIsoString meta.published
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
                            { url = meta.image
                            , alt = meta.description
                            , dimensions = Nothing
                            , mimeType = Nothing
                            }
                        , description = meta.description
                        , locale = Nothing
                        , title = meta.title
                        }
                        |> Seo.article
                            { tags = []
                            , section = Nothing
                            , publishedTime = Just (Date.toIsoString meta.published)
                            , modifiedTime = Nothing
                            , expirationTime = Nothing
                            }
                   )

        Metadata.BlogIndex ->
            Seo.summary
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.iconPng
                    , alt = "elm-pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = "elm-pages blog"
                }
                |> Seo.website

        Metadata.Showcase ->
            Seo.summary
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.iconPng
                    , alt = "elm-pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = "See some neat sites built using elm-pages! (Or submit yours!)"
                , locale = Nothing
                , title = "elm-pages sites showcase"
                }
                |> Seo.website


canonicalSiteUrl : String
canonicalSiteUrl =
    "https://elm-pages.com"


siteTagline : String
siteTagline =
    "A statically typed site generator - elm-pages"


tocView : MarkdownRenderer.TableOfContents -> Element msg
tocView toc =
    Element.column [ Element.alignTop, Element.spacing 20 ]
        [ Element.el [ Font.bold, Font.size 22 ] (Element.text "Table of Contents")
        , Element.column [ Element.spacing 10 ]
            (toc
                |> List.map
                    (\heading ->
                        Element.link [ Font.color (Element.rgb255 100 100 100) ]
                            { url = "#" ++ heading.anchorId
                            , label = Element.text heading.name
                            }
                    )
            )
        ]


publishedDateView metadata =
    Element.text
        (metadata.published
            |> Date.format "MMMM ddd, yyyy"
        )


githubRepoLink : Int -> Element msg
githubRepoLink starCount =
    Element.newTabLink []
        { url = "https://github.com/dillonkearns/elm-pages"
        , label =
            Element.row [ Element.spacing 5 ]
                [ Element.image
                    [ Element.width (Element.px 22)
                    , Font.color Palette.color.primary
                    ]
                    { src = ImagePath.toString Pages.images.github, description = "Github repo" }
                , Element.text <| String.fromInt starCount
                ]
        }


elmDocsLink : Element msg
elmDocsLink =
    Element.newTabLink []
        { url = "https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/"
        , label =
            Element.image
                [ Element.width (Element.px 22)
                , Font.color Palette.color.primary
                ]
                { src = ImagePath.toString Pages.images.elmLogo, description = "Elm Package Docs" }
        }
