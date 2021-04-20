module Pages.Internal.Platform.Effect exposing (..)

import DataSource exposing (RequestDetails)
import Pages.Internal.Platform.ToJsPayload exposing (ToJsPayload, ToJsSuccessPayloadNewCombined)


type Effect
    = NoEffect
    | SendJsData ToJsPayload
    | FetchHttp { masked : RequestDetails, unmasked : RequestDetails }
    | ReadFile String
    | GetGlob String
    | Batch (List Effect)
    | SendSinglePage ToJsSuccessPayloadNewCombined
    | Continue
