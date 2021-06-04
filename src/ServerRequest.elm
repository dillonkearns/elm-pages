module ServerRequest exposing (ServerRequest, expectHeader, init, optionalHeader, staticData, toStaticHttp)

{-|

@docs ServerRequest, expectHeader, init, optionalHeader, staticData, toStaticHttp

-}

import DataSource
import DataSource.Http
import OptimizedDecoder
import Secrets


{-| -}
type ServerRequest decodesTo
    = ServerRequest (OptimizedDecoder.Decoder decodesTo)


{-| -}
init : constructor -> ServerRequest constructor
init constructor =
    ServerRequest (OptimizedDecoder.succeed constructor)


{-| -}
staticData : DataSource.DataSource String
staticData =
    DataSource.Http.get (Secrets.succeed "$$elm-pages$$headers")
        (OptimizedDecoder.field "headers"
            (OptimizedDecoder.field "accept-language" OptimizedDecoder.string)
        )


{-| -}
toStaticHttp : ServerRequest decodesTo -> DataSource.DataSource decodesTo
toStaticHttp (ServerRequest decoder) =
    DataSource.Http.get (Secrets.succeed "$$elm-pages$$headers") decoder


{-| -}
expectHeader : String -> ServerRequest (String -> value) -> ServerRequest value
expectHeader headerName (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.field headerName OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
            )
        |> ServerRequest


{-| -}
optionalHeader : String -> ServerRequest (Maybe String -> value) -> ServerRequest value
optionalHeader headerName (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.optionalField headerName OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
            )
        |> ServerRequest
