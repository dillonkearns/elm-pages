module Pages.StaticHttpRequest exposing (Request(..))

import Dict exposing (Dict)
import Secrets exposing (Secrets)


type Request value
    = Request ( List (Secrets -> Result ( String, List String ) String), Dict String String -> Result String value )
