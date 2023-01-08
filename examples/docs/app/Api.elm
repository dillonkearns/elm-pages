module Api exposing (routes)

import ApiRoute
import Article
import BackendTask exposing (BackendTask)
import BackendTask.Http
import Exception exposing (Throwable)
import Head
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode
import Manifest
import Pages
import Pages.Manifest
import Route exposing (Route)
import Rss
import Site
import SiteOld
import Sitemap
import Time


routes :
    BackendTask Throwable (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ ApiRoute.succeed
        (\userId ->
            BackendTask.succeed
                (Json.Encode.object
                    [ ( "id", Json.Encode.string userId )
                    , ( "name"
                      , Html.p [] [ Html.text <| "Data for user " ++ userId ]
                            |> htmlToString Nothing
                            |> Json.Encode.string
                      )
                    ]
                    |> Json.Encode.encode 2
                )
        )
        |> ApiRoute.literal "users"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.literal ".json"
        |> ApiRoute.preRender
            (\route ->
                BackendTask.succeed
                    [ route "1"
                    , route "2"
                    , route "3"
                    ]
            )
    , ApiRoute.succeed
        (\repoName ->
            BackendTask.Http.getJson
                ("https://api.github.com/repos/dillonkearns/" ++ repoName)
                (Decode.field "stargazers_count" Decode.int)
                |> BackendTask.map
                    (\stars ->
                        Json.Encode.object
                            [ ( "repo", Json.Encode.string repoName )
                            , ( "stars", Json.Encode.int stars )
                            ]
                            |> Json.Encode.encode 2
                    )
                |> BackendTask.throw
        )
        |> ApiRoute.literal "repo"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.literal ".json"
        |> ApiRoute.preRender
            (\route ->
                BackendTask.succeed
                    [ route "elm-graphql"
                    ]
            )
    , rss
        { siteTagline = SiteOld.tagline
        , siteUrl = SiteOld.canonicalUrl
        , title = "elm-pages Blog"
        , builtAt = Pages.builtAt
        , indexPage = [ "blog" ]
        }
        postsBackendTask
    , ApiRoute.succeed
        (getStaticRoutes
            |> BackendTask.map
                (\allRoutes ->
                    allRoutes
                        |> List.map
                            (\route ->
                                { path = Route.routeToPath route |> String.join "/"
                                , lastMod = Nothing
                                }
                            )
                        |> Sitemap.build { siteUrl = "https://elm-pages.com" }
                )
        )
        |> ApiRoute.literal "sitemap.xml"
        |> ApiRoute.single
        |> ApiRoute.withGlobalHeadTags (BackendTask.succeed [ Head.sitemapLink "/sitemap.xml" ])
    , Pages.Manifest.generator Site.canonicalUrl Manifest.config
    ]


postsBackendTask : BackendTask Throwable (List Rss.Item)
postsBackendTask =
    Article.allMetadata
        |> BackendTask.map
            (List.map
                (\( route, article ) ->
                    { title = article.title
                    , description = article.description
                    , url =
                        route
                            |> Route.routeToPath
                            |> String.join "/"
                    , categories = []
                    , author = "Dillon Kearns"
                    , pubDate = Rss.Date article.published
                    , content = Nothing
                    , contentEncoded = Nothing
                    , enclosure = Nothing
                    }
                )
            )
        |> BackendTask.throw


rss :
    { siteTagline : String
    , siteUrl : String
    , title : String
    , builtAt : Time.Posix
    , indexPage : List String
    }
    -> BackendTask Throwable (List Rss.Item)
    -> ApiRoute.ApiRoute ApiRoute.Response
rss options itemsRequest =
    ApiRoute.succeed
        (itemsRequest
            |> BackendTask.map
                (\items ->
                    Rss.generate
                        { title = options.title
                        , description = options.siteTagline
                        , url = options.siteUrl ++ "/" ++ String.join "/" options.indexPage
                        , lastBuildTime = options.builtAt
                        , generator = Just "elm-pages"
                        , items = items
                        , siteUrl = options.siteUrl
                        }
                )
        )
        |> ApiRoute.literal "blog/feed.xml"
        |> ApiRoute.single
        |> ApiRoute.withGlobalHeadTags
            (BackendTask.succeed
                [ Head.rssLink "/blog/feed.xml"
                ]
            )
