module RunGreet exposing (run)

import BackendTask
import Coverage
import Greet exposing (Greeting(..))
import Pages.Script as Script exposing (Script)


run : Script
run =
    let
        _ =
            Coverage.track "RunGreet" 0
    in
    Script.withoutCliOptions
        (Script.log (Greet.greet Hello)
            |> Script.doThen
                (Script.log (Greet.greet Goodbye))
        )
