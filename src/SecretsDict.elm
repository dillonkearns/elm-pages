module SecretsDict exposing (SecretsDict, available, decoder, get, masked, unmasked)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)


available : SecretsDict -> List String
available secretsDict =
    case secretsDict of
        Masked ->
            []

        Unmasked dict ->
            Dict.keys dict


decoder : Decoder SecretsDict
decoder =
    Decode.dict Decode.string
        |> Decode.map Unmasked


unmasked : Dict String String -> SecretsDict
unmasked dict =
    Unmasked dict


masked : SecretsDict
masked =
    Masked


get : String -> SecretsDict -> Maybe String
get secretName secretsDict =
    case secretsDict of
        Masked ->
            Just <| "<" ++ secretName ++ ">"

        Unmasked dict ->
            dict |> Dict.get secretName


type SecretsDict
    = Masked
    | Unmasked (Dict String String)
