module Secrets exposing (..)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import TerminalText as Terminal


type alias UrlWithSecrets =
    Secrets -> Result BuildError String


type Secrets
    = Secrets (Dict String String)
    | Protected


protected : Secrets
protected =
    Protected


useFakeSecrets : (Secrets -> Result BuildError String) -> String
useFakeSecrets urlWithSecrets =
    urlWithSecrets protected
        |> Result.withDefault ""


empty =
    Secrets Dict.empty


get : String -> Secrets -> Result BuildError String
get name secretsData =
    case secretsData of
        Protected ->
            Ok ("<" ++ name ++ ">")

        Secrets secrets ->
            case Dict.get name secrets of
                Just secret ->
                    Ok secret

                Nothing ->
                    Err <| buildError name (Dict.keys secrets)


buildError : String -> List String -> BuildError
buildError secretName availableEnvironmentVariables =
    { message =
        [ Terminal.text "I expected to find this Secret in your environment variables but didn't find a match:\nSecrets.get \""
        , Terminal.red (Terminal.text secretName)
        , Terminal.text "\"\n\n"
        , Terminal.text "Maybe you meant one of:\n"
        , Terminal.text (String.join ", " availableEnvironmentVariables)
        ]
    }


decoder : Decoder Secrets
decoder =
    Decode.dict Decode.string
        |> Decode.map Secrets
