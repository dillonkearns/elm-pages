module InteropDefinitionsCli exposing (Flags, FromElm(..), ToElm, interop)

import Dict exposing (Dict)
import Json.Decode as JD
import Json.Encode as JE
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import SecretsDict exposing (SecretsDict)
import TsJson.Decode as TsDecode exposing (Decoder)
import TsJson.Encode as Encoder exposing (Encoder, optional, required)


interop :
    { toElm : Decoder ToElm
    , fromElm : Encoder FromElm
    , flags : TsDecode.Decoder Flags
    }
interop =
    { toElm = TsDecode.null ()
    , fromElm = fromElm
    , flags = flagsDecoder
    }


type alias Flags =
    { secrets : SecretsDict
    , mode : Mode
    , staticHttpCache : Dict String (Maybe String)
    }


flagsDecoder :
    TsDecode.Decoder
        { secrets : SecretsDict
        , mode : Mode
        , staticHttpCache : Dict String (Maybe String)
        }
flagsDecoder =
    TsDecode.map3
        (\secrets mode staticHttpCache ->
            { secrets = secrets
            , mode = mode
            , staticHttpCache = staticHttpCache
            }
        )
        (TsDecode.field "secrets" SecretsDict.tsDecoder)
        (TsDecode.field "mode" Mode.tsModeDecoder)
        (TsDecode.field "staticHttpCache"
            (TsDecode.dict
                (TsDecode.string
                    |> TsDecode.map Just
                )
            )
        )


type FromElm
    = SendPresenceHeartbeat
    | Alert String


type alias ToElm =
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
