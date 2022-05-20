module Pages.Transition exposing
    ( Transition(..), LoadingState(..)
    , FetcherState
    , FetcherSubmitStatus(..)
    )

{-|

@docs Transition, LoadingState


## Fetchers

@docs FetcherState, FetcherSubmitStatus

-}

import FormDecoder
import Path exposing (Path)


{-| -}
type Transition
    = Submitting FormDecoder.FormData
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
    }


{-| -}
type FetcherSubmitStatus
    = FetcherSubmitting
    | FetcherReloading
