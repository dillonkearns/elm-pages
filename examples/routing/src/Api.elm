module Api exposing (routes)

import ApiRoute
import DataSource
import DataSource.Http
import Html exposing (Html)
import Json.Encode
import OptimizedDecoder as Decode
import Secrets


routes :
    (Html Never -> String)
    -> List (ApiRoute.Done ApiRoute.Response)
routes htmlToString =
    []
