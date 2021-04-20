module RssPlugin exposing (generate)

import DataSource
import Head
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Builder)
import Rss
import Time


generate :
    { siteTagline : String
    , siteUrl : String
    , title : String
    , builtAt : Time.Posix
    , indexPage : PagePath
    }
    -> (item -> Maybe Rss.Item)
    -> DataSource.DataSource (List item)
    -> Builder pathKey userModel userMsg route
    -> Builder pathKey userModel userMsg route
generate options metadataToRssItem itemsRequest builder =
    let
        feedFilePath =
            (options.indexPage
                |> PagePath.toPath
            )
                ++ [ "feed.xml" ]
    in
    builder
        |> Pages.Platform.withFileGenerator
            (itemsRequest
                |> DataSource.map
                    (\items ->
                        { path = feedFilePath
                        , content =
                            Rss.generate
                                { title = options.title
                                , description = options.siteTagline

                                -- TODO make sure you don't add an extra "/"
                                , url = options.siteUrl ++ "/" ++ PagePath.toString options.indexPage
                                , lastBuildTime = options.builtAt
                                , generator = Just "elm-pages"
                                , items = items |> List.filterMap metadataToRssItem
                                , siteUrl = options.siteUrl
                                }
                        }
                            |> Ok
                            |> List.singleton
                    )
            )
        |> Pages.Platform.withGlobalHeadTags [ Head.rssLink (feedFilePath |> String.join "/") ]
