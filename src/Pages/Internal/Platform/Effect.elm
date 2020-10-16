module Pages.Internal.Platform.Effect exposing (..)

import Pages.Internal.Platform.ToJsPayload exposing (FileToGenerate, ToJsPayload, ToJsSuccessPayloadNew)
import Pages.Manifest as Manifest
import Pages.StaticHttp exposing (RequestDetails)


type Effect pathKey
    = NoEffect
    | SendJsData (ToJsPayload pathKey)
    | FetchHttp { masked : RequestDetails, unmasked : RequestDetails }
    | Batch (List (Effect pathKey))
    | SendSinglePage (ToJsSuccessPayloadNew pathKey)
    | SendInitialData
        { manifest : Manifest.Config pathKey
        , filesToGenerate : List FileToGenerate
        }
    | Continue
