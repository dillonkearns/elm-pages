module Pages.GeneratorProgramConfig exposing (GeneratorProgramConfig)

import Json.Decode as Decode
import Json.Encode
import Pages.Generator exposing (Generator)
import Pages.Internal.Platform.ToJsPayload


type alias GeneratorProgramConfig =
    { data : Generator
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , gotBatchSub : Sub Decode.Value
    , sendPageData : Pages.Internal.Platform.ToJsPayload.NewThingForPort -> Cmd Never
    }
