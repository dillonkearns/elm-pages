module MultiDict exposing (MultiDict, empty, get, insert, keys, remove, set)

import Dict exposing (Dict)
import List.Extra
import List.Nonempty as NonEmpty


type alias NonEmpty a =
    NonEmpty.Nonempty a


type MultiDict k v
    = MultiDict (Dict k (NonEmpty v))


empty : MultiDict k v
empty =
    MultiDict Dict.empty


insert : comparable -> v -> MultiDict comparable v -> MultiDict comparable v
insert key value (MultiDict dict) =
    MultiDict
        (Dict.update key (Maybe.map (NonEmpty.cons value) >> Maybe.withDefault (NonEmpty.fromElement value) >> Just) dict)


get : comparable -> MultiDict comparable v -> List v
get key (MultiDict dict) =
    Dict.get key dict
        |> Maybe.map NonEmpty.toList
        |> Maybe.withDefault []


keys : MultiDict k v -> List k
keys (MultiDict dict) =
    Dict.toList dict
        |> List.concatMap (\( k, vs ) -> List.repeat (NonEmpty.length vs) k)


remove : comparable -> v -> MultiDict comparable v -> MultiDict comparable v
remove key value (MultiDict dict) =
    MultiDict
        (Dict.update key (Maybe.andThen (NonEmpty.toList >> List.Extra.remove value >> NonEmpty.fromList)) dict)


set : comparable -> List v -> MultiDict comparable v -> MultiDict comparable v
set key values (MultiDict dict) =
    MultiDict
        (Dict.update key (\_ -> NonEmpty.fromList values) dict)
