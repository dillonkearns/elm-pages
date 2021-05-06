module Api exposing (routes)

import ApiRoute
import DataSource
import DataSource.Http
import Json.Encode
import OptimizedDecoder as Decode
import Secrets


routes : List (ApiRoute.Done ApiRoute.Response)
routes =
    [ ApiRoute.succeed
        (\userId ->
            DataSource.succeed
                { body =
                    Json.Encode.object
                        [ ( "id", Json.Encode.int userId )
                        , ( "name", Json.Encode.string ("Data for user " ++ String.fromInt userId) )
                        ]
                        |> Json.Encode.encode 2
                }
        )
        |> ApiRoute.literal "users"
        |> ApiRoute.slash
        |> ApiRoute.int
        |> ApiRoute.literal ".json"
        |> ApiRoute.buildTimeRoutes
            (\route ->
                DataSource.succeed
                    [ route 1
                    , route 2
                    , route 3
                    ]
            )
    , ApiRoute.succeed
        (\repoName ->
            DataSource.Http.get
                (Secrets.succeed ("https://api.github.com/repos/dillonkearns/" ++ repoName))
                (Decode.field "stargazers_count" Decode.int)
                |> DataSource.map
                    (\stars ->
                        { body =
                            Json.Encode.object
                                [ ( "repo", Json.Encode.string repoName )
                                , ( "stars", Json.Encode.int stars )
                                ]
                                |> Json.Encode.encode 2
                        }
                    )
        )
        |> ApiRoute.literal "repo"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.literal ".json"
        |> ApiRoute.buildTimeRoutes
            (\route ->
                DataSource.succeed
                    [ route "elm-graphql"
                    ]
            )

    --, ApiRoute.succeed
    --    (DataSource.succeed
    --        { body =
    --            allRoutes
    --                |> List.filterMap identity
    --                |> List.map
    --                    (\route ->
    --                        { path = Route.routeToPath (Just route) |> String.join "/"
    --                        , lastMod = Nothing
    --                        }
    --                    )
    --                |> Sitemap.build { siteUrl = "https://elm-pages.com" }
    --        }
    --    )
    --    |> ApiRoute.literal "sitemap.xml"
    --    |> ApiRoute.singleRoute
    ]
