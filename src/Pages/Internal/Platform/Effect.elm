module Pages.Internal.Platform.Effect exposing (Effect(..))

import Bytes exposing (Bytes)
import DataSource.Http exposing (RequestDetails)
import Pages.Internal.Platform.ToJsPayload exposing (ToJsSuccessPayloadNewCombined)


type Effect
    = NoEffect
    | FetchHttp RequestDetails
    | Batch (List Effect)
    | SendSinglePage ToJsSuccessPayloadNewCombined
    | SendSinglePageNew Bytes ToJsSuccessPayloadNewCombined
    | Continue
