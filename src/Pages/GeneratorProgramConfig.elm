module Pages.GeneratorProgramConfig exposing (GeneratorProgramConfig)

import Bytes exposing (Bytes)
import Json.Decode as Decode
import Json.Encode
import Pages.Internal.Platform.ToJsPayload
import Pages.Script exposing (Script)


type alias GeneratorProgramConfig =
    { data : Script
    , scriptModuleName : String
    , toJsPort : { json : Json.Encode.Value, bytes : List { key : String, data : Bytes } } -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , gotBatchSub : Sub (List { key : String, json : Decode.Value, bytes : Maybe Bytes })
    , sendPageData : Pages.Internal.Platform.ToJsPayload.NewThingForPort -> Cmd Never
    }
