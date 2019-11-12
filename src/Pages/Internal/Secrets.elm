module Pages.Internal.Secrets exposing (RequestDetails, Secrets(..), UnmaskedUrl, Url, UrlWithSecrets, get, unwrap)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Http


type Url
    = Url ( UnmaskedUrl, String )


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


type alias RequestDetails =
    { url : String, method : String, headers : List ( String, String ) }
