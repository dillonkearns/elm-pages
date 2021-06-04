module RequestsAndPending exposing (RequestsAndPending, decoder, get)

import Dict exposing (Dict)
import Json.Decode as Decode


type alias RequestsAndPending =
    Dict String (Maybe String)


get : String -> RequestsAndPending -> Maybe String
get key requestsAndPending =
    requestsAndPending
        |> Dict.get key
        |> Maybe.andThen identity


decoder : Decode.Decoder RequestsAndPending
decoder =
    Decode.dict (Decode.string |> Decode.map Just)
