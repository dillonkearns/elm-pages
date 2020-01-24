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
    { siteTagline : String
    , siteUrl : String
    }
    ->
        List
            { path : PagePath Pages.PathKey
            , frontmatter : Metadata
            , body : String
            }
    ->
        { path : List String
        , content : String
        }
fileToGenerate config siteMetadata =
    { path = [ "blog", "feed.xml" ]
    , content =
        generate config siteMetadata |> Xml.Encode.encode 0
    }


generate :
    { siteTagline : String
    , siteUrl : String
    }
    ->
        List
            { path : PagePath Pages.PathKey
            , frontmatter : Metadata
            , body : String
            }
    -> Xml.Value
generate { siteTagline, siteUrl } siteMetadata =
    RssFeed.generate
        { title = "elm-pages Blog"
        , description = siteTagline
        , url = "https://elm-pages.com/blog"
        , lastBuildTime = Pages.builtAt
        , generator = Just "elm-pages"
        , items = siteMetadata |> List.filterMap metadataToRssItem
        , siteUrl = siteUrl
        }


metadataToRssItem :
    { path : PagePath Pages.PathKey
    , frontmatter : Metadata
    , body : String
    }
    -> Maybe RssFeed.Item
metadataToRssItem page =
    case page.frontmatter of
        Article article ->
            Just
                { title = article.title
                , description = article.description
                , url = PagePath.toString page.path
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
