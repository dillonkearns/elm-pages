module Main exposing (main)

import Data.Author
import Global
import GlobalMetadata
import MarkdownRenderer
import MetadataNew
import MySitemap
import Pages
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Page)
import Rss
import RssPlugin
import Site
import TemplateDemultiplexer


main : Pages.Platform.Program TemplateDemultiplexer.Model TemplateDemultiplexer.Msg GlobalMetadata.Metadata Global.RenderedBody
main =
    TemplateDemultiplexer.mainTemplate
        { documents =
            [ { extension = "md"
              , metadata = MetadataNew.decoder
              , body = MarkdownRenderer.view
              }
            ]
        , manifest = Site.manifest
        , canonicalSiteUrl = Site.canonicalUrl
        , subscriptions = \_ -> Sub.none
        }
        |> RssPlugin.generate
            { siteTagline = Site.tagline
            , siteUrl = Site.canonicalUrl
            , title = "elm-pages Blog"
            , builtAt = Pages.builtAt
            , indexPage = Pages.pages.blog.index
            }
            metadataToRssItem
        |> MySitemap.install { siteUrl = Site.canonicalUrl } metadataToSitemapEntry
        |> Pages.Platform.toProgram


metadataToRssItem :
    { path : PagePath Pages.PathKey
    , frontmatter : GlobalMetadata.Metadata
    , body : String
    }
    -> Maybe Rss.Item
metadataToRssItem page =
    case page.frontmatter of
        GlobalMetadata.MetadataBlogPost blogPost ->
            if blogPost.draft then
                Nothing

            else
                Just
                    { title = blogPost.title
                    , description = blogPost.description
                    , url = PagePath.toString page.path
                    , categories = []
                    , author = blogPost.author.name
                    , pubDate = Rss.Date blogPost.published
                    , content = Nothing
                    }

        _ ->
            Nothing


metadataToSitemapEntry :
    List
        { path : PagePath Pages.PathKey
        , frontmatter : GlobalMetadata.Metadata
        , body : String
        }
    -> List { path : String, lastMod : Maybe String }
metadataToSitemapEntry siteMetadata =
    siteMetadata
        |> List.filter
            (\page ->
                case page.frontmatter of
                    GlobalMetadata.MetadataBlogPost blogPost ->
                        not blogPost.draft

                    _ ->
                        True
            )
        |> List.map
            (\page ->
                { path = PagePath.toString page.path, lastMod = Nothing }
            )
