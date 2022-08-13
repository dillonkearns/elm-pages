module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import DataSource.Http
import Html exposing (Html)
import Json.Decode
import Json.Encode
import MySession
import Pages.Manifest as Manifest
import Route exposing (Route)
import Server.Request
import Server.Response
import Server.Session as Session
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
        { name = "Site Name"
        , description = "Description"
        , startUrl = Route.Visibility__ { visibility = Nothing } |> Route.toPath
        , icons = []
        }
