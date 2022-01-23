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


type Session
    = Session (Dict String Value)


type alias Decoder decoded =
    OptimizedDecoder.Decoder decoded


type Value
    = Persistent String
    | ExpiringFlash String
    | NewFlash String


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


withFlash2 : String -> String -> Session -> Session
withFlash2 key value (Session session) =
    session
        |> Dict.insert key (NewFlash value)
        |> Session


insert : String -> String -> Session -> Session
insert key value (Session session) =
    session
        |> Dict.insert key (Persistent value)
        |> Session


get : String -> Session -> Maybe String
get key (Session session) =
    session
        |> Dict.get key
        |> Maybe.map unwrap


unwrap : Value -> String
unwrap value =
    case value of
        Persistent string ->
            string

        ExpiringFlash string ->
            string

        NewFlash string ->
            string


update : String -> (Maybe String -> Maybe String) -> Session -> Session
update key updateFn (Session session) =
    session
        |> Dict.update key
            (\maybeValue ->
                case maybeValue of
                    Just (Persistent value) ->
                        updateFn (Just value) |> Maybe.map Persistent

                    Just (ExpiringFlash value) ->
                        updateFn (Just value) |> Maybe.map NewFlash

                    Just (NewFlash value) ->
                        updateFn (Just value) |> Maybe.map NewFlash

                    Nothing ->
                        Nothing
                            |> updateFn
                            |> Maybe.map Persistent
            )
        |> Session


remove : String -> Session -> Session
remove key (Session session) =
    session
        |> Dict.remove key
        |> Session


empty : Session
empty =
    Session Dict.empty


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


setValues : Session -> Json.Encode.Value
setValues (Session session) =
    session
        |> Dict.toList
        |> List.filterMap
            (\( key, value ) ->
                case value of
                    Persistent string ->
                        Just ( key, string )

                    NewFlash string ->
                        Just ( flashPrefix ++ key, string )

                    ExpiringFlash _ ->
                        Nothing
            )
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


expectSession :
    { name : String
    , secrets : Secrets.Value (List String)
    , sameSite : String
    }
    -> Request request
    -> (request -> Result () Session -> DataSource ( Session, Response data ))
    -> Request (DataSource (Response data))
expectSession config userRequest toRequest =
    Request.map2
        (\sessionCookie userRequestData ->
            sessionCookie
                |> decryptCookie config
                |> DataSource.andThen
                    (encodeSessionUpdate config toRequest userRequestData)
        )
        (Request.expectCookie config.name)
        userRequest


withSession :
    { name : String
    , secrets : Secrets.Value (List String)
    , sameSite : String
    }
    -> Request request
    -> (request -> Result () (Maybe Session) -> DataSource ( Session, Response data ))
    -> Request (DataSource (Response data))
withSession config userRequest toRequest =
    Request.map2
        (\maybeSessionCookie userRequestData ->
            let
                decrypted : DataSource (Result () (Maybe Session))
                decrypted =
                    case maybeSessionCookie of
                        Just sessionCookie ->
                            sessionCookie
                                |> decryptCookie config
                                |> DataSource.map (Result.map Just)

                        Nothing ->
                            Ok Nothing
                                |> DataSource.succeed
            in
            decrypted
                |> DataSource.andThen
                    (encodeSessionUpdate config toRequest userRequestData)
        )
        (Request.cookie config.name)
        userRequest


encodeSessionUpdate config toRequest userRequestData sessionResult =
    sessionResult
        |> toRequest userRequestData
        |> DataSource.andThen
            (\( sessionUpdate, response ) ->
                DataSource.map
                    (\encoded ->
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
                    (encrypt config.secrets
                        (setValues sessionUpdate)
                    )
            )


decryptCookie : { a | secrets : Secrets.Value (List String) } -> String -> DataSource (Result () Session)
decryptCookie config sessionCookie =
    sessionCookie
        |> decrypt config.secrets (OptimizedDecoder.dict OptimizedDecoder.string)
        |> DataSource.map
            (Result.map
                (\dict ->
                    dict
                        |> Dict.toList
                        |> List.map
                            (\( key, value ) ->
                                if key |> String.startsWith flashPrefix then
                                    ( key |> String.dropLeft (flashPrefix |> String.length)
                                    , ExpiringFlash value
                                    )

                                else
                                    ( key, Persistent value )
                            )
                        |> Dict.fromList
                        |> Session
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


decrypt : Secrets.Value (List String) -> OptimizedDecoder.Decoder a -> String -> DataSource (Result () a)
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
        (OptimizedDecoder.nullable decoder |> OptimizedDecoder.map (Result.fromMaybe ()))
