port module GeneratedPorts exposing (decodeFlags, fromElm, toElm)

import InteropDefinitions
import Json.Decode
import Json.Encode
import TsJson.Decode as Decode
import TsJson.Encode as Encode



-- TODO decide whether to use type annotations or not
-- It simplifies the UX to skip the type annotations here, because the user doesn't
-- need to remember to expose the types
--
--fromElm : FromElm -> Cmd msg


fromElm value =
    value
        |> (InteropDefinitions.interop.fromElm |> Encode.encoder)
        |> interopFromElm



--toElm : Sub (Result Json.Decode.Error ToElm)


toElm =
    (InteropDefinitions.interop.toElm |> Decode.decoder)
        |> Json.Decode.decodeValue
        |> interopToElm



--decodeFlags : Json.Decode.Value -> Result Json.Decode.Error Flags


decodeFlags flags =
    Json.Decode.decodeValue
        (InteropDefinitions.interop.flags |> Decode.decoder)
        flags


port interopFromElm : Json.Encode.Value -> Cmd msg


port interopToElm : (Json.Decode.Value -> msg) -> Sub msg
