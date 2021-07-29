module DataSource.Port exposing (send)

{-|

@docs send

-}

import DataSource
import DataSource.Http
import Json.Encode
import OptimizedDecoder exposing (Decoder)
import Secrets


{-| -}
send : String -> Json.Encode.Value -> Decoder b -> DataSource.DataSource b
send portName input decoder =
    DataSource.Http.request
        (Secrets.succeed
            { url = "port://" ++ portName
            , method = "GET"
            , headers = []
            , body = DataSource.Http.jsonBody input
            }
        )
        decoder
