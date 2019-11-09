module Pages.Internal.Secrets exposing (RequestDetails, Secrets(..), UnmaskedUrl, Url, UrlWithSecrets, decoder, empty, get, hashRequest, masked, requestToString, stringToUrl, unwrap, urlWithoutSecrets, useFakeSecrets, useFakeSecrets2, useFakeSecrets3)

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
                |> .url
    in
    \secrets ->
        case f1 secrets of
            Ok unmaskedUrl ->
                Ok (Url ( UnmaskedUrl unmaskedUrl, maskedUrl ))

            Err error ->
                Err error


hashUrl : RequestDetails -> String
hashUrl requestDetails =
    "["
        ++ requestDetails.method
        ++ "]"
        ++ requestDetails.url


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
    Http.request
        { method = unmaskedUrl.method
        , url = unmaskedUrl.url
        , headers = []
        , body = Http.emptyBody
        , expect =
            Http.expectString
                (\response ->
                    gotResponse
                        { request = { url = maskedUrl, method = unmaskedUrl.method }
                        , response = response
                        }
                )
        , timeout = Nothing
        , tracker = Nothing
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


useFakeSecrets3 : (Secrets -> Result BuildError Url) -> RequestDetails
useFakeSecrets3 urlWithSecrets =
    urlWithSecrets protected
        |> Result.map
            (\(Url ( UnmaskedUrl unmaskedUrl, maskedUrl )) ->
                unmaskedUrl
            )
        |> Result.withDefault defaultRequest


useFakeSecrets2 : (Secrets -> Result BuildError a) -> a
useFakeSecrets2 urlWithSecrets =
    case urlWithSecrets protected of
        Ok value ->
            value

        Err _ ->
            Debug.todo "ERROR"


requestToString : RequestDetails -> String
requestToString requestDetails =
    requestDetails.url


hashRequest : RequestDetails -> String
hashRequest requestDetails =
    hashUrl requestDetails


defaultRequest : RequestDetails
defaultRequest =
    { url = "", method = "" }


empty =
    Secrets Dict.empty


decoder : Decoder Secrets
decoder =
    Decode.dict Decode.string
        |> Decode.map Secrets
