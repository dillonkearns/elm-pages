module Server.Session exposing
    ( withSession
    , NotLoadedReason(..)
    , Session, empty, get, insert, remove, update, withFlash
    )

{-| You can manage server state with HTTP cookies using this Server.Session API. Server-rendered pages define a `Server.Request.Parser`
to choose which requests to respond to and how to extract structured data from the incoming request.


## Using Sessions in a Request.Parser

Using these functions, you can store and read session data in cookies to maintain state between requests.
For example, TODO:

    action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
    action routeParams =
        MySession.withSession
            (Request.formDataWithServerValidation (form |> Form.initCombinedServer identity))
            (\nameResultData session ->
                nameResultData
                    |> BackendTask.map
                        (\nameResult ->
                            case nameResult of
                                Err errors ->
                                    ( session
                                        |> Result.withDefault Nothing
                                        |> Maybe.withDefault Session.empty
                                    , Response.render
                                        { errors = errors
                                        }
                                    )

                                Ok ( _, name ) ->
                                    ( session
                                        |> Result.withDefault Nothing
                                        |> Maybe.withDefault Session.empty
                                        |> Session.insert "name" name
                                        |> Session.withFlash "message" ("Welcome " ++ name ++ "!")
                                    , Route.redirectTo Route.Greet
                                    )
                        )
            )

The elm-pages framework will manage signing these cookies using the `secrets : BackendTask (List String)` you pass in.
That means that the values you set in your session will be directly visible to anyone who has access to the cookie
(so don't directly store sensitive data in your session). Since the session cookie is signed using the secret you provide,
the cookie will be invalidated if it is tampered with because it won't match when elm-pages verifies that it has been
signed with your secrets. Of course you need to provide secure secrets and treat your secrets with care.


### Rotating Secrets

The first String in `secrets : BackendTask (List String)` will be used to sign sessions, while the remaining String's will
still be used to attempt to "unsign" the cookies. So if you have a single secret:

    Session.withSession
        { name = "mysession"
        , secrets =
            BackendTask.map List.singleton
                (Env.expect "SESSION_SECRET2022-09-01")
        , options = cookieOptions
        }

Then you add a second secret

    Session.withSession
        { name = "mysession"
        , secrets =
            BackendTask.map2
                (\newSecret oldSecret -> [ newSecret, oldSecret ])
                (Env.expect "SESSION_SECRET2022-12-01")
                (Env.expect "SESSION_SECRET2022-09-01")
        , options = cookieOptions
        }

The new secret (`2022-12-01`) will be used to sign all requests. This API always re-signs using the newest secret in the list
whenever a new request comes in (even if the Session key-value pairs are unchanged), so these cookies get "refreshed" with the latest
signing secret when a new request comes in.

However, incoming requests with a cookie signed using the old secret (`2022-09-01`) will still successfully be unsigned
because they are still in the rotation (and then subsequently "refreshed" and signed using the new secret).

This allows you to rotate your session secrets (for security purposes). When a secret goes out of the rotation,
it will invalidate all cookies signed with that. For example, if we remove our old secret from the rotation:

    Session.withSession
        { name = "mysession"
        , secrets =
            BackendTask.map List.singleton
                (Env.expect "SESSION_SECRET2022-12-01")
        , options = cookieOptions
        }

And then a user makes a request but had a session signed with our old secret (`2022-09-01`), the session will be invalid
(so `withSession` would parse the session for that request as `Nothing`). It's standard for cookies to have an expiration date,
so there's nothing wrong with an old session expiring (and the browser will eventually delete old cookies), just be aware of that when rotating secrets.

@docs withSession

@docs NotLoadedReason


## Creating and Updating Sessions

@docs Session, empty, get, insert, remove, update, withFlash

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Dict exposing (Dict)
import Json.Decode
import Json.Encode
import Server.Request
import Server.Response exposing (Response)
import Server.SetCookie as SetCookie


{-| -}
type Session
    = Session (Dict String Value)


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
    = NoSessionCookie
    | InvalidSessionCookie


{-| -}
encodeNonExpiringPairs : Session -> Json.Encode.Value
encodeNonExpiringPairs (Session session) =
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
withSession :
    { name : String
    , secrets : BackendTask error (List String)
    , options : SetCookie.Options
    }
    -> (request -> Result NotLoadedReason Session -> BackendTask error ( Session, Response data errorPage ))
    -> Server.Request.Parser request
    -> Server.Request.Parser (BackendTask error (Response data errorPage))
withSession config toRequest userRequest =
    Server.Request.map2
        (\maybeSessionCookie userRequestData ->
            let
                unsigned : BackendTask error (Result NotLoadedReason Session)
                unsigned =
                    case maybeSessionCookie of
                        Just sessionCookie ->
                            sessionCookie
                                |> unsignCookie config
                                |> BackendTask.map
                                    (\unsignResult ->
                                        case unsignResult of
                                            Ok decoded ->
                                                Ok decoded

                                            Err () ->
                                                Err InvalidSessionCookie
                                    )

                        Nothing ->
                            Err NoSessionCookie
                                |> BackendTask.succeed
            in
            unsigned
                |> BackendTask.andThen
                    (encodeSessionUpdate config toRequest userRequestData)
        )
        (Server.Request.cookie config.name)
        userRequest


encodeSessionUpdate :
    { name : String
    , secrets : BackendTask error (List String)
    , options : SetCookie.Options
    }
    -> (c -> d -> BackendTask error ( Session, Response data errorPage ))
    -> c
    -> d
    -> BackendTask error (Response data errorPage)
encodeSessionUpdate config toRequest userRequestData sessionResult =
    sessionResult
        |> toRequest userRequestData
        |> BackendTask.andThen
            (\( sessionUpdate, response ) ->
                BackendTask.map
                    (\encoded ->
                        response
                            |> Server.Response.withSetCookieHeader
                                (SetCookie.setCookie config.name encoded config.options)
                    )
                    (sign config.secrets
                        (encodeNonExpiringPairs sessionUpdate)
                    )
            )


unsignCookie : { a | secrets : BackendTask error (List String) } -> String -> BackendTask error (Result () Session)
unsignCookie config sessionCookie =
    sessionCookie
        |> unsign config.secrets (Json.Decode.dict Json.Decode.string)
        |> BackendTask.map
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


sign : BackendTask error (List String) -> Json.Encode.Value -> BackendTask error String
sign getSecrets input =
    getSecrets
        |> BackendTask.andThen
            (\secrets ->
                BackendTask.Internal.Request.request
                    { name = "encrypt"
                    , body =
                        BackendTask.Http.jsonBody
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
                        BackendTask.Http.expectJson
                            Json.Decode.string
                    }
            )


unsign : BackendTask error (List String) -> Json.Decode.Decoder a -> String -> BackendTask error (Result () a)
unsign getSecrets decoder input =
    getSecrets
        |> BackendTask.andThen
            (\secrets ->
                BackendTask.Internal.Request.request
                    { name = "decrypt"
                    , body =
                        BackendTask.Http.jsonBody
                            (Json.Encode.object
                                [ ( "input", Json.Encode.string input )
                                , ( "secrets", Json.Encode.list Json.Encode.string secrets )
                                ]
                            )
                    , expect =
                        decoder
                            |> Json.Decode.nullable
                            |> Json.Decode.map (Result.fromMaybe ())
                            |> BackendTask.Http.expectJson
                    }
            )
