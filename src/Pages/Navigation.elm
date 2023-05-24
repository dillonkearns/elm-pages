module Pages.Navigation exposing (Navigation(..), LoadingState(..))

{-|

@docs Navigation, LoadingState

-}

import Form
import Pages.FormData exposing (FormData)
import Time
import UrlPath exposing (UrlPath)


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
