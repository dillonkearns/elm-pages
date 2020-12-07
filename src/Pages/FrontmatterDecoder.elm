module Pages.FrontmatterDecoder exposing (FrontmatterDecoder)

import Json.Decode as Decode exposing (Decoder)


type FrontmatterDecoder a
    = FrontmatterDecoder (List Decode.Value -> Decoder a)
