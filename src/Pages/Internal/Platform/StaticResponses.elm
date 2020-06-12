module Pages.Internal.Platform.StaticResponses exposing (..)

import Dict exposing (Dict)
import Dict.Extra
import Pages.Internal.ApplicationType as ApplicationType
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets


type alias StaticResponses =
    Dict String StaticHttpResult


type StaticHttpResult
    = NotFetched (StaticHttpRequest.Request ()) (Dict String (Result () String))


addEntry : Dict String (Maybe String) -> String -> Result () String -> StaticHttpResult -> StaticHttpResult
addEntry globalRawResponses hashedRequest rawResponse ((NotFetched request rawResponses) as entry) =
    let
        realUrls =
            globalRawResponses
                |> dictCompact
                |> StaticHttpRequest.resolveUrls ApplicationType.Cli request
                |> Tuple.second
                |> List.map Secrets.maskedLookup
                |> List.map HashRequest.hash

        includesUrl =
            List.member
                hashedRequest
                realUrls
    in
    if includesUrl then
        let
            updatedRawResponses =
                Dict.insert
                    hashedRequest
                    rawResponse
                    rawResponses
        in
        NotFetched request updatedRawResponses

    else
        entry


dictCompact : Dict String (Maybe a) -> Dict String a
dictCompact dict =
    dict
        |> Dict.Extra.filterMap (\key value -> value)
