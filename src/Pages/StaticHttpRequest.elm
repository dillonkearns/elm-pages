module Pages.StaticHttpRequest exposing (Request(..), urls)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Secrets exposing (Secrets)


type Request value
    = Request ( List (Secrets -> Result BuildError String), Dict String String -> Result String (Request value) )
    | Done value


urls : Request value -> List (Secrets -> Result BuildError String)
urls request =
    case request of
        Request ( urlList, lookupFn ) ->
            urlList

        Done value ->
            []
