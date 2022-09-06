module Pages.Transition exposing
    ( Transition(..), LoadingState(..)
    , FetcherState, FetcherSubmitStatus(..)
    , map
    )

{-|

@docs Transition, LoadingState


## Fetchers

@docs FetcherState, FetcherSubmitStatus

-}

import Form.FormData exposing (FormData)
import Path exposing (Path)
import Time


{-| -}
type Transition
    = Submitting FormData
    | LoadAfterSubmit FormData Path LoadingState
    | Loading Path LoadingState


{-| -}
type LoadingState
    = Redirecting
    | Load
    | ActionRedirect


{-| -}
type alias FetcherState actionData =
    { status : FetcherSubmitStatus actionData
    , payload : FormData
    , initiatedAt : Time.Posix
    }


{-| -}
type FetcherSubmitStatus actionData
    = FetcherSubmitting
    | FetcherReloading actionData
    | FetcherComplete actionData


map : (a -> b) -> FetcherState a -> FetcherState b
map mapFn fetcherState =
    { status = mapStatus mapFn fetcherState.status
    , payload = fetcherState.payload
    , initiatedAt = fetcherState.initiatedAt
    }


mapStatus : (a -> b) -> FetcherSubmitStatus a -> FetcherSubmitStatus b
mapStatus mapFn fetcherSubmitStatus =
    case fetcherSubmitStatus of
        FetcherSubmitting ->
            FetcherSubmitting

        FetcherReloading value ->
            FetcherReloading (mapFn value)

        FetcherComplete value ->
            FetcherComplete (mapFn value)
