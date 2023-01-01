module Pages.Internal.Script exposing (Script(..))

import BackendTask exposing (BackendTask)
import Cli.Program as Program
import Exception exposing (Throwable)
import Html exposing (Html)


{-| -}
type Script
    = Script
        ((Maybe { indent : Int, newLines : Bool }
          -> Html Never
          -> String
         )
         -> Program.Config (BackendTask Throwable ())
        )
