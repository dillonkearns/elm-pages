module Api exposing (routes)

import ApiRoute
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Pages.Manifest as Manifest
import Route exposing (Route)
import Site


routes :
    BackendTask FatalError (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ BackendTask.succeed manifest |> Manifest.generator Site.canonicalUrl
    ]


manifest : Manifest.Config
manifest =
    Manifest.init
        { name = "Site Name"
        , description = "Description"
        , startUrl = Route.Visibility__ { visibility = Nothing } |> Route.toPath
        , icons = []
        }
