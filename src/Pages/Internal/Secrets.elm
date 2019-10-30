module Pages.Internal.Secrets exposing (Secrets(..), decoder, empty, useFakeSecrets)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)


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


decoder : Decoder Secrets
decoder =
    Decode.dict Decode.string
        |> Decode.map Secrets
