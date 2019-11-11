module Secrets2 exposing (Value, append, lookup, map, maskedLookup, succeed, with)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Json.Decode.Exploration as Decode
import SecretsDict exposing (SecretsDict)


type Value value
    = Value (SecretsDict -> Result (List String) value)


lookup : SecretsDict -> Value a -> Result (List BuildError) a
lookup secrets (Value lookupSecrets) =
    lookupSecrets secrets
        -- TODO
        |> Result.mapError (\_ -> [])


maskedLookup : Value value -> value
maskedLookup (Value lookupSecrets) =
    case lookupSecrets SecretsDict.masked of
        Ok value ->
            value

        Err error ->
            -- crash
            maskedLookup (Value lookupSecrets)


type SecretsLookup
    = Masked
    | Unmasked (Dict String String)


succeed : value -> Value value
succeed value =
    Value (\_ -> Ok value)


append : Value (List value) -> Value (List value) -> Value (List value)
append (Value lookupSecrets1) (Value lookupSecrets2) =
    Value
        (\secrets ->
            let
                secrets1 : Result (List String) (List value)
                secrets1 =
                    lookupSecrets1 secrets

                secrets2 : Result (List String) (List value)
                secrets2 =
                    lookupSecrets2 secrets
            in
            case ( secrets1, secrets2 ) of
                ( Ok value1, Ok value2 ) ->
                    Ok (value1 ++ value2)

                ( Ok value1, Err errors2 ) ->
                    Err errors2

                ( Err errors1, Ok value2 ) ->
                    Err errors1

                ( Err errors1, Err errors2 ) ->
                    Err (errors1 ++ errors2)
        )


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
            case lookupSecrets (secrets |> Debug.log "LOOKING UP") of
                Ok value ->
                    case SecretsDict.get newSecret secrets |> Debug.log "GOT" of
                        Just newValue ->
                            value newValue |> Ok

                        Nothing ->
                            Err [ newSecret ]

                Err error ->
                    case SecretsDict.get newSecret secrets of
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
