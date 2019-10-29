module Pages.StaticHttpRequest exposing (Request(..))

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Secrets exposing (Secrets)


type Request value
    = Request ( List (Secrets -> Result BuildError String), Dict String String -> Result String value )
