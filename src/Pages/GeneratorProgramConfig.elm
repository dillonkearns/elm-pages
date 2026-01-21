module Pages.GeneratorProgramConfig exposing (GeneratorProgramConfig)

import Json.Decode as Decode
import Json.Encode
import Pages.Internal.Platform.ToJsPayload
import Pages.Script exposing (StatefulScript)


type alias GeneratorProgramConfig model msg =
    { data : StatefulScript model msg
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , gotBatchSub : Sub Decode.Value
    , sendPageData : Pages.Internal.Platform.ToJsPayload.NewThingForPort -> Cmd Never
    }
