module Secrets exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)


type alias UrlWithSecrets =
    Secrets -> Result String String


type Secrets
    = Secrets (Dict String String)
    | Protected


protected : Secrets
protected =
    Protected


useFakeSecrets : (Secrets -> Result String String) -> String
useFakeSecrets urlWithSecrets =
    urlWithSecrets protected
        |> Result.withDefault ""


empty =
    Secrets Dict.empty


get : String -> Secrets -> Result String String
get name secretsData =
    case secretsData of
        Protected ->
            Ok ("<" ++ name ++ ">")

        Secrets secrets ->
            case Dict.get name secrets of
                Just secret ->
                    Ok secret

                Nothing ->
                    Err <| name


decoder : Decoder Secrets
decoder =
    Decode.dict Decode.string
        |> Decode.map Secrets
