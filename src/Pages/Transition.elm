module Pages.Transition exposing (Transition(..), LoadingState(..))

{-|

@docs Transition, LoadingState

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
