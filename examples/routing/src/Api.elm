module Api exposing (routes)

import ApiRoute
import DataSource exposing (DataSource)
import DataSource.Http
import Html exposing (Html)
import Json.Encode
import OptimizedDecoder as Decode
import Route exposing (Route)
import Secrets


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    []
