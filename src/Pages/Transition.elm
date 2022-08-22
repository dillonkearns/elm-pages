module Pages.Transition exposing
    ( Transition(..), LoadingState(..)
    , FetcherState, FetcherSubmitStatus(..)
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
type alias FetcherState =
    { status : FetcherSubmitStatus
    , payload : FormData
    , initiatedAt : Time.Posix
    }


{-| -}
type FetcherSubmitStatus
    = FetcherSubmitting
    | FetcherReloading
