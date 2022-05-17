module Pages.Transition exposing (..)


type Transition
    = Idle
    | Submitting
    | Loading


type LoadingState
    = Redirecting
    | Load
    | ActionRedirect
