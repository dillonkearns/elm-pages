module Pages.Internal.Script exposing (Script(..))

import Cli.Program as Program
import DataSource exposing (DataSource)
import Exception exposing (Throwable)
import Html exposing (Html)


{-| -}
type Script
    = Script
        ((Maybe { indent : Int, newLines : Bool }
          -> Html Never
          -> String
         )
         -> Program.Config (DataSource Throwable ())
        )
