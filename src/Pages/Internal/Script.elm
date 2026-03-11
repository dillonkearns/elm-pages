module Pages.Internal.Script exposing (Script(..))

import BackendTask exposing (BackendTask)
import Cli.Program as Program
import FatalError exposing (FatalError)
import Html exposing (Html)
import Json.Encode as Encode


{-| -}
type Script
    = Script
        { cliConfig :
            String
            ->
                (Maybe { indent : Int, newLines : Bool }
                 -> Html Never
                 -> String
                )
            -> Program.Config (BackendTask FatalError ())
        , introspect : Maybe ({ moduleName : String, path : String } -> Encode.Value)
        }
