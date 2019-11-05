module Pages.Internal.Secrets exposing (RequestDetails, Secrets(..), UnmaskedUrl, Url, UrlWithSecrets, decoder, empty, get, hashRequest, masked, requestToString, stringToUrl, unwrap, urlWithoutSecrets, useFakeSecrets, useFakeSecrets2)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Http
import Json.Decode as Decode exposing (Decoder)


stringToUrl : (Secrets -> Result BuildError { url : String, method : String }) -> (Secrets -> Result BuildError Url)
stringToUrl f1 =
    let
        maskedUrl =
            -- TODO hash it and mask it here
            useFakeSecrets2 f1
    in
    \secrets ->
        case f1 secrets of
            Ok unmaskedUrl ->
                Ok (Url ( UnmaskedUrl unmaskedUrl, maskedUrl.url ))

            Err error ->
                Err error


urlWithoutSecrets : { url : String, method : String } -> UrlWithSecrets
urlWithoutSecrets rawUrlWithoutSecrets =
    stringToUrl (\secrets -> Ok rawUrlWithoutSecrets)


type Url
    = Url ( UnmaskedUrl, String )


masked : Url -> String
masked (Url ( _, maskedUrl )) =
    maskedUrl


type UnmaskedUrl
    = UnmaskedUrl { url : String, method : String }


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
        |> Result.withDefault (Url ( UnmaskedUrl { url = "", method = "" }, "" ))
        |> masked


type alias RequestDetails =
    { url : String, method : String }


useFakeSecrets2 : (Secrets -> Result BuildError RequestDetails) -> RequestDetails
useFakeSecrets2 urlWithSecrets =
    urlWithSecrets protected
        |> Result.withDefault defaultRequest


requestToString : RequestDetails -> String
requestToString requestDetails =
    requestDetails.url


hashRequest : RequestDetails -> String
hashRequest requestDetails =
    requestDetails.url


defaultRequest : RequestDetails
defaultRequest =
    { url = "", method = "" }


empty =
    Secrets Dict.empty


decoder : Decoder Secrets
decoder =
    Decode.dict Decode.string
        |> Decode.map Secrets
