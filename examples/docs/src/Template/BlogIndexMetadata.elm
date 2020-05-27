module Template.BlogIndexMetadata exposing (..)

import Json.Decode as Decode exposing (Decoder)


type alias Metadata =
    {}


decoder : Decoder Metadata
decoder =
    Decode.succeed Metadata
