module PageServerResponse exposing (map, PageServerResponse(..))

{-|

@docs map, PageServerResponse

-}

import Server.Response exposing (Response)


{-| -}
type PageServerResponse data
    = RenderPage data
    | ServerResponse Response


{-| -}
map : (data -> mappedData) -> PageServerResponse data -> PageServerResponse mappedData
map mapFn pageServerResponse =
    case pageServerResponse of
        RenderPage data ->
            RenderPage (mapFn data)

        ServerResponse serverResponse ->
            ServerResponse serverResponse
