module Api exposing (routes)

import ApiRoute
import Html exposing (Html)


routes :
    (Html Never -> String)
    -> List (ApiRoute.Done ApiRoute.Response)
routes htmlToString =
    []
