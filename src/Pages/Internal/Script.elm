module Pages.Internal.Script exposing (Script(..))

import BackendTask exposing (BackendTask)
import Cli.Program as Program
import FatalError exposing (FatalError)
import Html exposing (Html)


{-| -}
type Script
    = Script
        ((Maybe { indent : Int, newLines : Bool }
          -> Html Never
          -> String
         )
         -> Program.Config (BackendTask FatalError ())
        )
