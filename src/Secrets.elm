module Secrets exposing (..)

import Dict exposing (Dict)


type Secrets
    = Secrets (Dict String String)


empty =
    Secrets Dict.empty


get : String -> Secrets -> Result String String
get name (Secrets secrets) =
    case Dict.get name secrets of
        Just secret ->
            Ok secret

        Nothing ->
            Err <| "Couldn't find secret `" ++ name ++ "`"
