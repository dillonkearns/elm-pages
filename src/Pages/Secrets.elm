module Pages.Secrets exposing (Value, map, succeed, with)

{-| TODO

@docs Value, map, succeed, with

-}

import Secrets


{-| TODO
-}
type alias Value value =
    Secrets.Value value


{-| TODO
-}
succeed : value -> Value value
succeed =
    Secrets.succeed


{-| TODO
-}
map : (valueA -> valueB) -> Value valueA -> Value valueB
map =
    Secrets.map


{-| TODO
-}
with : String -> Value (String -> value) -> Value value
with =
    Secrets.with
