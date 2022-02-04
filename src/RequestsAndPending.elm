module RequestsAndPending exposing (RequestsAndPending, get)

import Dict exposing (Dict)


type alias RequestsAndPending =
    Dict String (Maybe String)


get : String -> RequestsAndPending -> Maybe String
get key requestsAndPending =
    requestsAndPending
        |> Dict.get key
        |> Maybe.andThen identity
