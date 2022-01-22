module Session exposing (..)

import DataSource exposing (DataSource)
import DataSource.Http
import Dict exposing (Dict)
import Dict.Extra
import Json.Decode
import Json.Encode
import OptimizedDecoder
import Secrets
import Server.Request as Request exposing (Request)
import Server.Response exposing (Response)
import Server.SetCookie as SetCookie


type Session decoded
    = Session decoded


type alias Decoder decoded =
    OptimizedDecoder.Decoder decoded


type SessionUpdate
    = SessionUpdate (Dict String String)


noUpdates : SessionUpdate
noUpdates =
    SessionUpdate Dict.empty


oneUpdate : String -> String -> SessionUpdate
oneUpdate string value =
    SessionUpdate (Dict.singleton string value)


updateAllFields : Dict String String -> SessionUpdate
updateAllFields updates =
    SessionUpdate updates


withFlash : String -> String -> SessionUpdate -> SessionUpdate
withFlash string value (SessionUpdate sessionUpdate) =
    SessionUpdate (sessionUpdate |> Dict.insert (flashPrefix ++ string) value)


flash : String -> String -> SessionUpdate
flash string value =
    SessionUpdate (Dict.singleton (flashPrefix ++ string) value)


type NotLoadedReason
    = NoCookies
    | MissingHeaders


succeed : constructor -> Decoder constructor
succeed constructor =
    constructor
        |> OptimizedDecoder.succeed


setValues : SessionUpdate -> Dict String String -> Json.Encode.Value
setValues (SessionUpdate dict) original =
    Dict.union dict original
        |> Dict.toList
        |> List.map (Tuple.mapSecond Json.Encode.string)
        |> Json.Encode.object


flashPrefix : String
flashPrefix =
    "__flash__"


clearFlashCookies : Dict String String -> Dict String String
clearFlashCookies dict =
    Dict.Extra.removeWhen
        (\key _ ->
            key |> String.startsWith flashPrefix
        )
        dict


withSession :
    { name : String
    , secrets : Secrets.Value (List String)
    , sameSite : String
    }
    -> Request request
    -> (request -> Result String (Dict String String) -> DataSource ( SessionUpdate, Response data ))
    -> Request (DataSource (Response data))
withSession config userRequest toRequest =
    Request.map2
        (\maybeSessionCookie userRequestData ->
            let
                decrypted : DataSource (Result String (Dict String String))
                decrypted =
                    case maybeSessionCookie of
                        Just sessionCookie ->
                            sessionCookie
                                |> decrypt config.secrets (OptimizedDecoder.dict OptimizedDecoder.string)
                                |> DataSource.map
                                    (Dict.Extra.mapKeys
                                        (\key ->
                                            if key |> String.startsWith flashPrefix then
                                                key |> String.dropLeft (flashPrefix |> String.length)

                                            else
                                                key
                                        )
                                    )
                                |> DataSource.map Ok

                        Nothing ->
                            Err "TODO"
                                |> DataSource.succeed

                decryptedFull : DataSource (Dict String String)
                decryptedFull =
                    maybeSessionCookie
                        |> Maybe.map
                            (\sessionCookie -> decrypt config.secrets (OptimizedDecoder.dict OptimizedDecoder.string) sessionCookie)
                        |> Maybe.withDefault (DataSource.succeed Dict.empty)
            in
            decryptedFull
                |> DataSource.andThen
                    (\cookieDict ->
                        decrypted
                            |> DataSource.andThen
                                (\thing ->
                                    let
                                        otherThing =
                                            toRequest userRequestData thing
                                    in
                                    otherThing
                                        |> DataSource.andThen
                                            (\( sessionUpdate, response ) ->
                                                let
                                                    encodedCookie : Json.Encode.Value
                                                    encodedCookie =
                                                        setValues sessionUpdate (cookieDict |> clearFlashCookies)
                                                in
                                                DataSource.map2
                                                    (\encoded originalCookieValues ->
                                                        response
                                                            |> Server.Response.withSetCookieHeader
                                                                (SetCookie.setCookie config.name encoded
                                                                    |> SetCookie.httpOnly
                                                                    |> SetCookie.withPath "/"
                                                                 -- TODO set expiration time
                                                                 -- TODO do I need to encrypt the session expiration as part of it
                                                                 -- TODO should I update the expiration time every time?
                                                                 --|> SetCookie.withExpiration (Time.millisToPosix 100000000000)
                                                                )
                                                    )
                                                    (encrypt config.secrets encodedCookie)
                                                    decryptedFull
                                            )
                                )
                    )
        )
        (Request.cookie config.name)
        userRequest


encrypt : Secrets.Value (List String) -> Json.Encode.Value -> DataSource String
encrypt secrets input =
    DataSource.Http.request
        (secrets
            |> Secrets.map
                (\secretList ->
                    { url = "port://encrypt"
                    , method = "GET"
                    , headers = []

                    -- TODO pass through secrets here
                    , body =
                        DataSource.Http.jsonBody
                            (Json.Encode.object
                                [ ( "values", input )
                                , ( "secret"
                                  , Json.Encode.string
                                        (secretList
                                            |> List.head
                                            -- TODO use different default - require non-empty list?
                                            |> Maybe.withDefault ""
                                        )
                                  )
                                ]
                            )
                    }
                )
        )
        OptimizedDecoder.string


decrypt : Secrets.Value (List String) -> OptimizedDecoder.Decoder a -> String -> DataSource a
decrypt secrets decoder input =
    DataSource.Http.request
        (secrets
            |> Secrets.map
                (\secretList ->
                    { url = "port://decrypt"
                    , method = "GET"
                    , headers = []
                    , body =
                        DataSource.Http.jsonBody
                            (Json.Encode.object
                                [ ( "input", Json.Encode.string input )
                                , ( "secrets", Json.Encode.list Json.Encode.string secretList )
                                ]
                            )
                    }
                )
        )
        decoder
