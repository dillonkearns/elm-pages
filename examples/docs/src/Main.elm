module Main exposing (main)

import Cloudinary
import Color
import Data.Author
import Head
import MimeType
import MySitemap
import NoMetadata exposing (NoMetadata(..))
import Pages exposing (images, pages)
import Pages.ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform
import Rss
import RssPlugin
import Shared
import Site
import Template.Blog.Slug_
import TemplateModulesBeta


webp : MimeType.MimeImage
webp =
    MimeType.OtherImage "webp"


icon :
    MimeType.MimeImage
    -> Int
    -> Manifest.Icon pathKey
icon format width =
    { src = cloudinaryIcon format width
    , sizes = [ ( width, width ) ]
    , mimeType = format |> Just
    , purposes = [ Manifest.IconPurposeAny, Manifest.IconPurposeMaskable ]
    }


cloudinaryIcon :
    MimeType.MimeImage
    -> Int
    -> ImagePath pathKey
cloudinaryIcon mimeType width =
    Cloudinary.urlSquare "v1603234028/elm-pages/elm-pages-icon" (Just mimeType) width


socialIcon : ImagePath pathKey
socialIcon =
    Cloudinary.urlSquare "v1603234028/elm-pages/elm-pages-icon" Nothing 250


main : Pages.Platform.Program TemplateModulesBeta.Model TemplateModulesBeta.Msg (Maybe TemplateModulesBeta.Route) Pages.PathKey
main =
    TemplateModulesBeta.mainTemplate
        { site = Site.config
        }
        |> RssPlugin.generate
            { siteTagline = Site.tagline
            , siteUrl = Site.canonicalUrl
            , title = "elm-pages Blog"
            , builtAt = Pages.builtAt
            , indexPage = Pages.pages.index
            }
            Template.Blog.Slug_.toRssItem
            Template.Blog.Slug_.articlesRequest
        |> Pages.Platform.withGlobalHeadTags
            [ Head.icon [ ( 32, 32 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 32)
            , Head.icon [ ( 16, 16 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 16)
            , Head.appleTouchIcon (Just 180) (cloudinaryIcon MimeType.Png 180)
            , Head.appleTouchIcon (Just 192) (cloudinaryIcon MimeType.Png 192)
            ]
        |> Pages.Platform.toProgram


metadataToRssItem :
    { path : PagePath Pages.PathKey
    , frontmatter : NoMetadata
    , body : String
    }
    -> Maybe Rss.Item
metadataToRssItem page =
    case page.frontmatter of
        --TemplateType.BlogPost blogPost ->
        --    if blogPost.draft then
        --        Nothing
        --
        --    else
        --        Just
        --            { title = blogPost.title
        --            , description = blogPost.description
        --            , url = PagePath.toString page.path
        --            , categories = []
        --            , author = blogPost.author.name
        --            , pubDate = Rss.Date blogPost.published
        --            , content = Nothing
        --            }
        --
        _ ->
            Nothing


metadataToSitemapEntry :
    List
        { path : PagePath Pages.PathKey
        , frontmatter : NoMetadata
        , body : String
        }
    -> List { path : String, lastMod : Maybe String }
metadataToSitemapEntry siteMetadata =
    siteMetadata
        |> List.filter
            (\page ->
                case page.frontmatter of
                    --    TemplateType.BlogPost blogPost ->
                    --        not blogPost.draft
                    --
                    _ ->
                        True
            )
        |> List.map
            (\page ->
                { path = PagePath.toString page.path, lastMod = Nothing }
            )
