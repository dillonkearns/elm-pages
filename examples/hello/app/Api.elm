module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import BackendTask exposing (BackendTask)
import Html exposing (Html)
import Pages.Manifest as Manifest
import Route exposing (Route)


routes :
    BackendTask (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    []


manifest : Manifest.Config
manifest =
    Manifest.init
        { name = "Site Name"
        , description = "Description"
        , startUrl = Route.Index |> Route.toPath
        , icons = []
        }
