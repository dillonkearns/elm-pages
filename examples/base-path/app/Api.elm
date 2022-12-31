module Api exposing (routes)

import ApiRoute
import DataSource exposing (DataSource)
import Exception exposing (Throwable)
import Html exposing (Html)
import Route exposing (Route)


routes :
    DataSource Throwable (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    []
