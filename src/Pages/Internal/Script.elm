module Pages.Internal.Script exposing (Script(..))

import Cli.Program as Program
import DataSource exposing (DataSource)
import Html exposing (Html)


{-| -}
type Script
    = Script
        ((Maybe { indent : Int, newLines : Bool }
          -> Html Never
          -> String
         )
         -> Program.Config (DataSource ())
        )
