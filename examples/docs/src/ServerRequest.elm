module ServerRequest exposing (ServerRequest, expectHeader, init, optionalHeader, staticData, toStaticHttp)

import Internal.OptimizedDecoder exposing (OptimizedDecoder)
import OptimizedDecoder
import Pages.StaticHttp as StaticHttp
import Secrets


type ServerRequest decodesTo
    = ServerRequest (OptimizedDecoder.Decoder decodesTo)


init : constructor -> ServerRequest constructor
init constructor =
    ServerRequest (OptimizedDecoder.succeed constructor)


staticData : StaticHttp.Request String
staticData =
    StaticHttp.get (Secrets.succeed "$$elm-pages$$headers")
        (OptimizedDecoder.field "headers"
            (OptimizedDecoder.field "accept-language" OptimizedDecoder.string)
        )


toStaticHttp : ServerRequest decodesTo -> StaticHttp.Request decodesTo
toStaticHttp (ServerRequest decoder) =
    StaticHttp.get (Secrets.succeed "$$elm-pages$$headers") decoder


expectHeader : String -> ServerRequest (String -> value) -> ServerRequest value
expectHeader headerName (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.field headerName OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
            )
        |> ServerRequest


optionalHeader : String -> ServerRequest (Maybe String -> value) -> ServerRequest value
optionalHeader headerName (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.optionalField headerName OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
            )
        |> ServerRequest
