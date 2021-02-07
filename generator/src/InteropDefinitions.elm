module InteropDefinitions exposing (Flags, interop)

import InteropDefinitionsCli
import Json.Decode as JD
import Json.Encode as JE
import TsJson.Decode as TsDecode exposing (Decoder)
import TsJson.Encode as Encoder exposing (Encoder, optional, required)



--interop : { toElm : Decoder ToElm, fromElm : Encoder FromElm, flags : TsDecode.Decoder Flags }


interop =
    InteropDefinitionsCli.interop


type alias Flags =
    InteropDefinitionsCli.Flags
