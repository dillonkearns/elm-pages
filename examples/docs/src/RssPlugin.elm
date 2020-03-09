module RssPlugin exposing (..)

import Head
import Pages.Builder exposing (Builder)
import Pages.Directory as Directory exposing (Directory)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Rss
import Time


generate :
    Directory pathKey hasIndex
    ->
        { siteTagline : String
        , siteUrl : String
        , title : String
        , builtAt : Time.Posix
        , indexPage : PagePath pathKey
        }
    ->
        ({ path : PagePath pathKey
         , frontmatter : metadata
         , body : String
         }
         -> Maybe Rss.Item
        )
    -> Builder pathKey userModel userMsg metadata view builderState
    -> Builder pathKey userModel userMsg metadata view builderState
generate baseDirectory options metadataToRssItem builder =
    let
        feedFilePath =
            Directory.basePath baseDirectory ++ [ "feed.xml" ]
    in
    builder
        |> Pages.Builder.withFileGenerator
            (\siteMetadata ->
                { path = feedFilePath
                , content =
                    Rss.generate
                        { title = options.title
                        , description = options.siteTagline

                        -- TODO make sure you don't add an extra "/"
                        , url = options.siteUrl ++ "/" ++ PagePath.toString options.indexPage
                        , lastBuildTime = options.builtAt
                        , generator = Just "elm-pages"
                        , items = siteMetadata |> List.filterMap metadataToRssItem
                        , siteUrl = options.siteUrl
                        }
                }
                    |> Ok
                    |> List.singleton
                    |> StaticHttp.succeed
            )
        |> Pages.Builder.addGlobalHeadTags [ Head.rssLink (feedFilePath |> String.join "/") ]
