module RequestsAndPending exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode
import List.Extra as Dict


type alias RequestsAndPending =
    Dict String (Maybe String)


init : RequestsAndPending
init =
    Dict.empty


get : String -> RequestsAndPending -> Maybe String
get key requestsAndPending =
    requestsAndPending
        |> Dict.get key
        |> Maybe.andThen identity


insert : String -> String -> RequestsAndPending -> RequestsAndPending
insert key value requestsAndPending =
    Dict.insert key (Just value) requestsAndPending


decoder : Decode.Decoder RequestsAndPending
decoder =
    Decode.dict (Decode.string |> Decode.map Just)
