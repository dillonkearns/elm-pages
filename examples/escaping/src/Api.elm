module Api exposing (routes)

import ApiRoute
import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import Html exposing (Html)
import Route exposing (Route)


routes :
    DataSource BuildError (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    []
