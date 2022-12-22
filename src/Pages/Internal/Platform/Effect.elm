module Pages.Internal.Platform.Effect exposing (Effect(..))

import Bytes exposing (Bytes)
import Pages.Internal.Platform.ToJsPayload exposing (ToJsSuccessPayloadNewCombined)
import Pages.StaticHttp.Request as StaticHttp


type Effect
    = NoEffect
    | FetchHttp StaticHttp.Request
    | Batch (List Effect)
    | SendSinglePage ToJsSuccessPayloadNewCombined
    | SendSinglePageNew Bytes ToJsSuccessPayloadNewCombined
