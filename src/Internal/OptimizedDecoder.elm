module Internal.OptimizedDecoder exposing (OptimizedDecoder(..), jd, jde)

import Json.Decode
import Json.Decode.Exploration


type OptimizedDecoder a
    = OptimizedDecoder (Json.Decode.Decoder a) (Json.Decode.Exploration.Decoder a)


jd : OptimizedDecoder a -> Json.Decode.Decoder a
jd (OptimizedDecoder jd_ jde_) =
    jd_


jde : OptimizedDecoder a -> Json.Decode.Exploration.Decoder a
jde (OptimizedDecoder jd_ jde_) =
    jde_
