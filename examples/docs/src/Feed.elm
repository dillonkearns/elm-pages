module Feed exposing (fileToGenerate)

import Dict
import Metadata exposing (Metadata(..))
import Pages
import Pages.PagePath as PagePath exposing (PagePath)
import RssFeed
import Time
import Xml
import Xml.Encode exposing (..)


fileToGenerate :
    String
    ->
        List
            { path : PagePath Pages.PathKey
            , frontmatter : Metadata
            }
    ->
        { path : List String
        , content : String
        }
fileToGenerate siteTagline siteMetadata =
    { path = [ "feed.xml" ]
    , content =
        generate siteTagline siteMetadata |> Xml.Encode.encode 0
    }


generate :
    String
    ->
        List
            { path : PagePath Pages.PathKey
            , frontmatter : Metadata
            }
    -> Xml.Value
generate siteTagline siteMetadata =
    RssFeed.generate
        { title = "elm-pages Blog"
        , description = siteTagline
        , url = "https://elm-pages.com/blog"
        , lastBuildTime = Pages.builtAt
        , generator =
            Just
                { name = "elm-pages"
                , uri = Just "https://elm-pages.com"
                , version = Nothing
                }
        , items = siteMetadata |> List.filterMap metadataToRssItem
        }


metadataToRssItem :
    { path : PagePath Pages.PathKey
    , frontmatter : Metadata
    }
    -> Maybe RssFeed.Item
metadataToRssItem page =
    case page.frontmatter of
        Article article ->
            Just
                { title = article.title
                , description = article.description
                , url = PagePath.toString page.path
                , guid = PagePath.toString page.path
                , categories = []
                , author = article.author.name
                , pubDate = article.published
                , content = Nothing
                }

        Page pageMetadata ->
            Nothing

        Doc docMetadata ->
            Nothing

        Author author ->
            Nothing

        BlogIndex ->
            Nothing
