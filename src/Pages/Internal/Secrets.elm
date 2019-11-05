module Pages.Internal.Secrets exposing (RequestDetails, Secrets(..), UnmaskedUrl, Url, UrlWithSecrets, decoder, empty, get, masked, stringToUrl, unwrap, urlWithoutSecrets, useFakeSecrets, useFakeSecrets2)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Http
import Json.Decode as Decode exposing (Decoder)


stringToUrl : (Secrets -> Result BuildError String) -> (Secrets -> Result BuildError Url)
stringToUrl f1 =
    let
        maskedUrl =
            useFakeSecrets2 f1
    in
    \secrets ->
        case f1 secrets of
            Ok unmaskedUrl ->
                Ok (Url ( UnmaskedUrl { url = unmaskedUrl }, maskedUrl ))

            Err error ->
                Err error


urlWithoutSecrets : String -> UrlWithSecrets
urlWithoutSecrets rawUrlWithoutSecrets =
    \secrets -> Ok (Url ( UnmaskedUrl { url = rawUrlWithoutSecrets }, rawUrlWithoutSecrets ))


type Url
    = Url ( UnmaskedUrl, String )


masked : Url -> String
masked (Url ( _, maskedUrl )) =
    maskedUrl


type UnmaskedUrl
    = UnmaskedUrl { url : String }


type alias RequestDetails =
    { url : String }


get (Url ( UnmaskedUrl unmaskedUrl, maskedUrl )) gotResponse =
    Http.get
        { url = unmaskedUrl.url
        , expect =
            Http.expectString
                (\response ->
                    gotResponse
                        { url = maskedUrl
                        , response = response
                        }
                )
        }


unwrap (Url ( UnmaskedUrl unmaskedUrl, maskedUrl )) =
    { unmasked = unmaskedUrl
    , masked = maskedUrl
    }


type alias UrlWithSecrets =
    Secrets -> Result BuildError Url


type Secrets
    = Secrets (Dict String String)
    | Protected


protected : Secrets
protected =
    Protected


useFakeSecrets : UrlWithSecrets -> String
useFakeSecrets urlWithSecrets =
    urlWithSecrets protected
        |> Result.withDefault (Url ( UnmaskedUrl { url = "" }, "" ))
        |> masked


useFakeSecrets2 : (Secrets -> Result BuildError String) -> String
useFakeSecrets2 urlWithSecrets =
    urlWithSecrets protected
        |> Result.withDefault ""


empty =
    Secrets Dict.empty


decoder : Decoder Secrets
decoder =
    Decode.dict Decode.string
        |> Decode.map Secrets
