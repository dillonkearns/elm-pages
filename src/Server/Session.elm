module Server.Session exposing (Decoder, NotLoadedReason(..), Session(..), Value(..), empty, expectSession, flashPrefix, get, insert, remove, setValues, succeed, unwrap, update, withFlash, withSession)

{-|

@docs Decoder, NotLoadedReason, Session, Value, empty, expectSession, flashPrefix, get, insert, remove, setValues, succeed, unwrap, update, withFlash, withSession

-}

import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.Internal.Request
import Dict exposing (Dict)
import Json.Decode
import Json.Encode
import Server.Request as Request exposing (Parser)
import Server.Response exposing (Response)
import Server.SetCookie as SetCookie


{-| -}
type Session
    = Session (Dict String Value)


{-| -}
type alias Decoder decoded =
    Json.Decode.Decoder decoded


{-| -}
type Value
    = Persistent String
    | ExpiringFlash String
    | NewFlash String


{-| -}
withFlash : String -> String -> Session -> Session
withFlash key value (Session session) =
    session
        |> Dict.insert key (NewFlash value)
        |> Session


{-| -}
insert : String -> String -> Session -> Session
insert key value (Session session) =
    session
        |> Dict.insert key (Persistent value)
        |> Session


{-| -}
get : String -> Session -> Maybe String
get key (Session session) =
    session
        |> Dict.get key
        |> Maybe.map unwrap


{-| -}
unwrap : Value -> String
unwrap value =
    case value of
        Persistent string ->
            string

        ExpiringFlash string ->
            string

        NewFlash string ->
            string


{-| -}
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


{-| -}
remove : String -> Session -> Session
remove key (Session session) =
    session
        |> Dict.remove key
        |> Session


{-| -}
empty : Session
empty =
    Session Dict.empty


{-| -}
type NotLoadedReason
    = NoCookies
    | MissingHeaders


{-| -}
succeed : constructor -> Decoder constructor
succeed constructor =
    constructor
        |> Json.Decode.succeed


{-| -}
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


{-| -}
flashPrefix : String
flashPrefix =
    "__flash__"


{-| -}
expectSession :
    { name : String
    , secrets : DataSource (List String)
    , options : SetCookie.Options
    }
    -> Parser request
    -> (request -> Result () Session -> DataSource ( Session, Response data errorPage ))
    -> Parser (DataSource (Response data errorPage))
expectSession config userRequest toRequest =
    Request.map2
        (\sessionCookie userRequestData ->
            sessionCookie
                |> unsignCookie config
                |> DataSource.andThen
                    (encodeSessionUpdate config toRequest userRequestData)
        )
        (Request.expectCookie config.name)
        userRequest


{-| -}
withSession :
    { name : String
    , secrets : DataSource (List String)
    , options : SetCookie.Options
    }
    -> Parser request
    -> (request -> Result () (Maybe Session) -> DataSource ( Session, Response data errorPage ))
    -> Parser (DataSource (Response data errorPage))
withSession config userRequest toRequest =
    Request.map2
        (\maybeSessionCookie userRequestData ->
            let
                unsigned : DataSource (Result () (Maybe Session))
                unsigned =
                    case maybeSessionCookie of
                        Just sessionCookie ->
                            sessionCookie
                                |> unsignCookie config
                                |> DataSource.map (Result.map Just)

                        Nothing ->
                            Ok Nothing
                                |> DataSource.succeed
            in
            unsigned
                |> DataSource.andThen
                    (encodeSessionUpdate config toRequest userRequestData)
        )
        (Request.cookie config.name)
        userRequest


encodeSessionUpdate :
    { name : String
    , secrets : DataSource (List String)
    , options : SetCookie.Options
    }
    -> (c -> d -> DataSource ( Session, Response data errorPage ))
    -> c
    -> d
    -> DataSource (Response data errorPage)
encodeSessionUpdate config toRequest userRequestData sessionResult =
    sessionResult
        |> toRequest userRequestData
        |> DataSource.andThen
            (\( sessionUpdate, response ) ->
                DataSource.map
                    (\encoded ->
                        response
                            |> Server.Response.withSetCookieHeader
                                (SetCookie.setCookie config.name encoded config.options)
                    )
                    (sign config.secrets
                        (setValues sessionUpdate)
                    )
            )


unsignCookie : { a | secrets : DataSource (List String) } -> String -> DataSource (Result () Session)
unsignCookie config sessionCookie =
    sessionCookie
        |> unsign config.secrets (Json.Decode.dict Json.Decode.string)
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


sign : DataSource (List String) -> Json.Encode.Value -> DataSource String
sign getSecrets input =
    getSecrets
        |> DataSource.andThen
            (\secrets ->
                DataSource.Internal.Request.request
                    { name = "encrypt"
                    , body =
                        DataSource.Http.jsonBody
                            (Json.Encode.object
                                [ ( "values", input )
                                , ( "secret"
                                  , Json.Encode.string
                                        (secrets
                                            |> List.head
                                            -- TODO use different default - require non-empty list?
                                            |> Maybe.withDefault ""
                                        )
                                  )
                                ]
                            )
                    , expect =
                        DataSource.Http.expectJson
                            Json.Decode.string
                    }
            )


unsign : DataSource (List String) -> Json.Decode.Decoder a -> String -> DataSource (Result () a)
unsign getSecrets decoder input =
    getSecrets
        |> DataSource.andThen
            (\secrets ->
                DataSource.Internal.Request.request
                    { name = "decrypt"
                    , body =
                        DataSource.Http.jsonBody
                            (Json.Encode.object
                                [ ( "input", Json.Encode.string input )
                                , ( "secrets", Json.Encode.list Json.Encode.string secrets )
                                ]
                            )
                    , expect =
                        decoder
                            |> Json.Decode.nullable
                            |> Json.Decode.map (Result.fromMaybe ())
                            |> DataSource.Http.expectJson
                    }
            )
