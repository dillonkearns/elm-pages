module Secrets2 exposing (Value, map, succeed, with)

import Dict exposing (Dict)
import Json.Decode.Exploration as Decode


type Value value
    = Value (Dict String String -> Result (List String) value)


succeed : value -> Value value
succeed value =
    Value (\_ -> Ok value)


map : (valueA -> valueB) -> Value valueA -> Value valueB
map mapFunction (Value lookupSecrets) =
    Value
        (\secrets ->
            lookupSecrets secrets
                |> Result.map mapFunction
        )


with : String -> Value (String -> value) -> Value value
with newSecret (Value lookupSecrets) =
    Value <|
        \secrets ->
            case lookupSecrets secrets of
                Ok value ->
                    case Dict.get newSecret secrets of
                        Just newValue ->
                            value newValue |> Ok

                        Nothing ->
                            Err [ newSecret ]

                Err error ->
                    case Dict.get newSecret secrets of
                        Just newValue ->
                            Err error

                        Nothing ->
                            -- TODO add more errors
                            Err (newSecret :: error)



--            lookupSecrets secrets
--                |> Result.map ((|>) "")


example =
    request
        (succeed { url = "https://api.github.com/repos/dillonkearns/elm-pages", method = "GET" })
        (Decode.succeed ())


example2 =
    request
        (succeed
            (\mySecret secret2 ->
                { url = "https://api.github.com/repos/dillonkearns/elm-pages?secret=" ++ mySecret, method = "GET" }
            )
            |> with "SECRET"
            |> with "SECRET2"
        )
        (Decode.succeed ())



{-
   StaticHttp.request
       (Secrets.succeed
       { url = "https://api.github.com/repos/dillonkearns/elm-pages"
       , method = "GET"
       })
       (Decode.succeed ())

-}


request : Value { url : String, method : String } -> Decode.Decoder a -> ()
request withSecrets decoder =
    ()
