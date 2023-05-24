module Pages.Navigation exposing
    ( LoadingState(..), map, FormData
    , FetcherState, FetcherSubmitStatus(..)
    , Navigation(..)
    )

{-|

@docs Transition, LoadingState, map, FormData


## Fetchers

@docs FetcherState, FetcherSubmitStatus

-}

import Form
import Time
import UrlPath exposing (UrlPath)


{-| -}
type alias FormData =
    { fields : List ( String, String )
    , method : Form.Method
    , action : String
    , id : Maybe String
    }


{-| -}
type Navigation
    = Submitting FormData
    | LoadAfterSubmit FormData UrlPath LoadingState
    | Loading UrlPath LoadingState


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


{-| -}
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
