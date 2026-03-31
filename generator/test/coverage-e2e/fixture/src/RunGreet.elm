module RunGreet exposing (run)

import BackendTask
import Greet exposing (Greeting(..))
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log (Greet.greet Hello)
            |> Script.doThen
                (Script.log (Greet.greet Goodbye))
        )
