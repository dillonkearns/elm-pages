module Pages.Transition exposing
    ( Transition(..), LoadingState(..)
    , FetcherState, FetcherSubmitStatus(..)
    )

{-|

@docs Transition, LoadingState


## Fetchers

@docs FetcherState, FetcherSubmitStatus

-}

import FormDecoder
import Path exposing (Path)
import Time


{-| -}
type Transition
    = Submitting FormDecoder.FormData
    | LoadAfterSubmit FormDecoder.FormData Path LoadingState
    | Loading Path LoadingState


{-| -}
type LoadingState
    = Redirecting
    | Load
    | ActionRedirect


{-| -}
type alias FetcherState =
    { status : FetcherSubmitStatus
    , payload : FormDecoder.FormData
    , initiatedAt : Time.Posix
    }


{-| -}
type FetcherSubmitStatus
    = FetcherSubmitting
    | FetcherReloading
