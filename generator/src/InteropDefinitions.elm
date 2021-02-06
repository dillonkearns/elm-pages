module InteropDefinitions exposing (Flags, FromElm(..), ToElm, interop)

import Json.Decode as JD
import Json.Encode as JE
import TsJson.Decode as Decode exposing (Decoder)
import TsJson.Encode as Encoder exposing (Encoder, optional, required)


interop : { toElm : Decoder ToElm, fromElm : Encoder FromElm, flags : Decode.Decoder Flags }
interop =
    { toElm = Decode.null ()
    , fromElm = fromElm
    , flags = Decode.null ()
    }


type FromElm
    = SendPresenceHeartbeat
    | Alert String


type alias ToElm =
    ()


type alias Flags =
    ()


fromElm : Encoder.Encoder FromElm
fromElm =
    Encoder.union
        (\vSendHeartbeat vAlert value ->
            case value of
                SendPresenceHeartbeat ->
                    vSendHeartbeat

                Alert string ->
                    vAlert string
        )
        |> Encoder.variant0 "SendPresenceHeartbeat"
        |> Encoder.variantObject "Alert" [ required "message" identity Encoder.string ]
        |> Encoder.buildUnion
