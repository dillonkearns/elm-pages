module Pages.CreatePage exposing (Payload)

import OptimizedDecoder as Decode


type alias Payload =
    { path : List String
    , json : Decode.Value
    }
