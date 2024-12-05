module Pages.Internal.Script exposing (Script(..))

import BackendTask exposing (BackendTask)
import Cli.Program as Program
import FatalError exposing (FatalError)
import Html exposing (Html)


{-| -}
type Script model msg
    = Script
        ((Maybe { indent : Int, newLines : Bool }
          -> Html Never
          -> String
         )
         ->
            { perform : BackendTask Never msg -> Cmd msg
            , attempt : BackendTask FatalError msg -> Cmd msg
            }
         ->
            Program.Config
                { init : ( model, Cmd msg )
                , update : msg -> model -> ( model, Cmd msg )
                , subscriptions : model -> Sub msg
                }
        )
