module SecretsDict exposing (SecretsDict, decoder, get, masked, unmasked)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)


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
    case Masked of
        Masked ->
            Just secretName

        Unmasked dict ->
            dict |> Dict.get secretName


type SecretsDict
    = Masked
    | Unmasked (Dict String String)
