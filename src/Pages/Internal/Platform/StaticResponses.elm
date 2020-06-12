module Pages.Internal.Platform.StaticResponses exposing (..)

import Dict exposing (Dict)
import Pages.StaticHttpRequest as StaticHttpRequest


type alias StaticResponses =
    Dict String StaticHttpResult


type StaticHttpResult
    = NotFetched (StaticHttpRequest.Request ()) (Dict String (Result () String))
