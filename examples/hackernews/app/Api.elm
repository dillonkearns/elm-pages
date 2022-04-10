module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import Html exposing (Html)
import Pages.Manifest as Manifest
import Route exposing (Route)
import Site


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ DataSource.succeed manifest |> Manifest.generator Site.canonicalUrl
    ]


manifest : Manifest.Config
manifest =
    Manifest.init
        { name = "Hacker News Clone"
        , description = "elm-pages port of Hacker News"
        , startUrl = Route.Feed__ { feed = Nothing } |> Route.toPath
        , icons = []
        }
