module Pages.Internal.Platform.Effect exposing (Effect(..))

import Bytes exposing (Bytes)
import DataSource.Http exposing (RequestDetails)
import Pages.Internal.Platform.ToJsPayload exposing (ToJsSuccessPayloadNewCombined)
import Pages.StaticHttp.Request as StaticHttp


type Effect
    = NoEffect
    | FetchHttp Bool StaticHttp.Request
    | Batch (List Effect)
    | SendSinglePage ToJsSuccessPayloadNewCombined
    | SendSinglePageNew Bytes ToJsSuccessPayloadNewCombined
    | Continue
