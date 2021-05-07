module Api exposing (routes)

import ApiRoute
import DataSource
import DataSource.Http
import Json.Encode
import OptimizedDecoder as Decode
import Secrets


routes : List (ApiRoute.Done ApiRoute.Response)
routes =
    []
