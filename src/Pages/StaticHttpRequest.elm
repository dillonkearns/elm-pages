module Pages.StaticHttpRequest exposing (Request(..))

import Dict exposing (Dict)


type Request value
    = Request ( List String, Dict String String -> Result String value )
