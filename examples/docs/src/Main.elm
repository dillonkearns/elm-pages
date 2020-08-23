module Main exposing (main)

import Color
import Data.Author
import Date
import DocSidebar
import DocumentSvg
import Element exposing (Element)
import Element.Events
import Element.Font as Font
import Element.Region
import FontAwesome
import Global
import GlobalMetadata
import Head
import Head.Seo as Seo
import Html.Attributes as Attr
import MarkdownRenderer
import Metadata exposing (Metadata)
import MetadataNew
import Pages exposing (images, pages)
import Pages.Directory as Directory exposing (Directory)
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Page)
import Palette
import Rss
import SiteConfig
import StructuredData
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


main : Pages.Platform.Program TemplateDemultiplexer.Model TemplateDemultiplexer.Msg GlobalMetadata.Metadata Global.View
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
        , subscriptions = \_ -> Sub.none
        }
        |> Pages.Platform.toProgram



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


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/abouts-cards>
<https://htmlhead.dev>
<https://html.spec.whatwg.org/multipage/semantics.html#standard-metadata-names>
<https://ogp.me/>
-}
head : PagePath Pages.PathKey -> Metadata -> List (Head.Tag Pages.PathKey)
head currentPath metadata =
    case metadata of
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

        _ ->
            Debug.todo ""


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
