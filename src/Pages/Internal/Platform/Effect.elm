module Pages.Internal.Platform.Effect exposing (..)

import Pages.Internal.Platform.ToJsPayload exposing (ToJsPayload)
import Pages.StaticHttp exposing (RequestDetails)


type Effect pathKey
    = NoEffect
    | SendJsData (ToJsPayload pathKey)
    | FetchHttp { masked : RequestDetails, unmasked : RequestDetails }
    | Batch (List (Effect pathKey))
