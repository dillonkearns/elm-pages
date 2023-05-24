module Pages.ConcurrentSubmission exposing
    ( ConcurrentSubmission, Status(..)
    , map
    )

{-|

@docs ConcurrentSubmission, Status

@docs map

-}

import Pages.FormData exposing (FormData)
import Time


{-| -}
type alias ConcurrentSubmission actionData =
    { status : Status actionData
    , payload : FormData
    , initiatedAt : Time.Posix
    }


{-| -}
type Status actionData
    = Submitting
    | Reloading actionData
    | Complete actionData


{-| -}
map : (a -> b) -> ConcurrentSubmission a -> ConcurrentSubmission b
map mapFn fetcherState =
    { status = mapStatus mapFn fetcherState.status
    , payload = fetcherState.payload
    , initiatedAt = fetcherState.initiatedAt
    }


mapStatus : (a -> b) -> Status a -> Status b
mapStatus mapFn fetcherSubmitStatus =
    case fetcherSubmitStatus of
        Submitting ->
            Submitting

        Reloading value ->
            Reloading (mapFn value)

        Complete value ->
            Complete (mapFn value)
