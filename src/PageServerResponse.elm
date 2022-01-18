module PageServerResponse exposing
    ( map, PageServerResponse(..)
    , render
    )

{-|

@docs map, PageServerResponse

-}

import Server.Response exposing (Response)


{-| -}
type PageServerResponse data
    = RenderPage
        { statusCode : Int
        , headers : List ( String, String )
        }
        data
    | ServerResponse Response


render : data -> PageServerResponse data
render data =
    RenderPage
        { statusCode = 200, headers = [] }
        data


{-| -}
map : (data -> mappedData) -> PageServerResponse data -> PageServerResponse mappedData
map mapFn pageServerResponse =
    case pageServerResponse of
        RenderPage response data ->
            RenderPage response (mapFn data)

        ServerResponse serverResponse ->
            ServerResponse serverResponse
