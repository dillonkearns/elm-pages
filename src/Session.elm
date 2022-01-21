module Session exposing (..)

import DataSource exposing (DataSource)
import DataSource.Http
import Dict exposing (Dict)
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
    = SessionUpdate (Dict String Json.Encode.Value)


noUpdates : SessionUpdate
noUpdates =
    SessionUpdate Dict.empty


oneUpdate : String -> Json.Encode.Value -> SessionUpdate
oneUpdate string value =
    SessionUpdate (Dict.singleton string value)


type NotLoadedReason
    = NoCookies
    | MissingHeaders


succeed : constructor -> Decoder constructor
succeed constructor =
    constructor
        |> OptimizedDecoder.succeed


setValues : SessionUpdate -> Dict String Json.Decode.Value -> Json.Encode.Value
setValues (SessionUpdate dict) original =
    Dict.union dict original
        |> Dict.toList
        |> Json.Encode.object


withSession :
    { name : String
    , secrets : Secrets.Value (List String)
    , sameSite : String
    }
    -> Decoder decoded
    -> (Result String decoded -> DataSource ( SessionUpdate, Response data ))
    -> Request (DataSource (Response data))
withSession config decoder toRequest =
    Request.cookie config.name
        |> Request.map
            (\maybeSessionCookie ->
                let
                    decrypted : DataSource (Result String decoded)
                    decrypted =
                        case maybeSessionCookie of
                            Just sessionCookie ->
                                decrypt config.secrets decoder sessionCookie
                                    |> DataSource.map Ok

                            Nothing ->
                                Err "TODO"
                                    |> DataSource.succeed

                    decryptedFull : DataSource (Dict String OptimizedDecoder.Value)
                    decryptedFull =
                        maybeSessionCookie
                            |> Maybe.map
                                (\sessionCookie -> decrypt config.secrets (OptimizedDecoder.dict OptimizedDecoder.value) sessionCookie)
                            |> Maybe.withDefault (DataSource.succeed Dict.empty)
                in
                decryptedFull
                    |> DataSource.andThen
                        (\cookieDict ->
                            DataSource.andThen
                                (\thing ->
                                    let
                                        otherThing =
                                            toRequest thing
                                    in
                                    otherThing
                                        |> DataSource.andThen
                                            (\( sessionUpdate, response ) ->
                                                let
                                                    encodedCookie : Json.Encode.Value
                                                    encodedCookie =
                                                        setValues sessionUpdate cookieDict
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
                                decrypted
                        )
            )


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
