module DataSource.Port exposing (..)

import DataSource
import DataSource.Http
import Json.Encode
import OptimizedDecoder exposing (Decoder)
import Secrets


send : Json.Encode.Value -> Decoder b -> DataSource.DataSource b
send input decoder =
    DataSource.Http.request
        (Secrets.succeed
            { url = "port://port"
            , method = "GET"
            , headers = []
            , body = DataSource.jsonBody input
            }
        )
        decoder
