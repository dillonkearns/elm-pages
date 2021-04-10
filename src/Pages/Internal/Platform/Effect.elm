module Pages.Internal.Platform.Effect exposing (..)

import Pages.Internal.Platform.ToJsPayload exposing (ToJsPayload, ToJsSuccessPayloadNewCombined)
import Pages.StaticHttp exposing (RequestDetails)


type Effect
    = NoEffect
    | SendJsData ToJsPayload
    | FetchHttp { masked : RequestDetails, unmasked : RequestDetails }
    | ReadFile String
    | GetGlob String
    | Batch (List Effect)
    | SendSinglePage ToJsSuccessPayloadNewCombined
    | Continue
