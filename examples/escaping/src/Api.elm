module Api exposing (routes)

import ApiRoute
import BackendTask exposing (BackendTask)
import Exception exposing (Throwable)
import Html exposing (Html)
import Route exposing (Route)


routes :
    BackendTask Throwable (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    []
