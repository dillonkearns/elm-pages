module Server.Session exposing
    ( withSession, withSessionResult
    , NotLoadedReason(..)
    , Session, empty, get, insert, remove, update, withFlash
    )

{-| You can manage server state with HTTP cookies using this Server.Session API. Server-rendered routes have a `Server.Request.Request`
argument that lets you inspect the incoming HTTP request, and return a response using the `Server.Response.Response` type.

This API provides a higher-level abstraction for extracting data from the HTTP request, and setting data in the HTTP response.
It manages the session through key-value data stored in cookies, and lets you [`insert`](#insert), [`update`](#update), and [`remove`](#remove)
values from the Session. It also provides an abstraction for flash session values through [`withFlash`](#withFlash).


## Using Sessions

Using these functions, you can store and read session data in cookies to maintain state between requests.

    import Server.Session as Session

    secrets : BackendTask FatalError (List String)
    secrets =
        Env.expect "SESSION_SECRET"
            |> BackendTask.allowFatal
            |> BackendTask.map List.singleton

    type alias Data =
        { darkMode : Bool }

    data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
    data routeParams request =
        request
            |> Session.withSession
                { name = "mysession"
                , secrets = secrets
                , options = Nothing
                }
                (\session ->
                    let
                        darkMode : Bool
                        darkMode =
                            (session |> Session.get "mode" |> Maybe.withDefault "light")
                                == "dark"
                    in
                    BackendTask.succeed
                        ( session
                        , Response.render
                            { darkMode = darkMode
                            }
                        )
                )

The elm-pages framework will manage signing these cookies using the `secrets : BackendTask FatalError (List String)` you pass in.
That means that the values you set in your session will be directly visible to anyone who has access to the cookie
(so don't directly store sensitive data in your session). Since the session cookie is signed using the secret you provide,
the cookie will be invalidated if it is tampered with because it won't match when elm-pages verifies that it has been
signed with your secrets. Of course you need to provide secure secrets and treat your secrets with care.


### Rotating Secrets

The first String in `secrets : BackendTask FatalError (List String)` will be used to sign sessions, while the remaining String's will
still be used to attempt to "unsign" the cookies. So if you have a single secret:

    Session.withSession
        { name = "mysession"
        , secrets =
            BackendTask.map List.singleton
                (Env.expect "SESSION_SECRET2022-09-01")
        , options = Nothing
        }

Then you add a second secret

    Session.withSession
        { name = "mysession"
        , secrets =
            BackendTask.map2
                (\newSecret oldSecret -> [ newSecret, oldSecret ])
                (Env.expect "SESSION_SECRET2022-12-01")
                (Env.expect "SESSION_SECRET2022-09-01")
        , options = Nothing
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
        , options = Nothing
        }

And then a user makes a request but had a session signed with our old secret (`2022-09-01`), the session will be invalid
(so `withSession` would parse the session for that request as `Nothing`). It's standard for cookies to have an expiration date,
so there's nothing wrong with an old session expiring (and the browser will eventually delete old cookies), just be aware of that when rotating secrets.

@docs withSession, withSessionResult

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
import Server.Request exposing (Request)
import Server.Response exposing (Response)
import Server.SetCookie as SetCookie


{-| Represents a Session with key-value Strings.

Use with `withSession` to read in the `Session`, and encode any changes you make to the `Session` back through cookie storage
via the outgoing HTTP response.

-}
type Session
    = Session (Dict String Value)


{-| -}
type Value
    = Persistent String
    | ExpiringFlash String
    | NewFlash String


{-| Flash session values are values that are only available for the next request.

    session
        |> Session.withFlash "message" "Your payment was successful!"

-}
withFlash : String -> String -> Session -> Session
withFlash key value (Session session) =
    session
        |> Dict.insert key (NewFlash value)
        |> Session


{-| Insert a value under the given key in the `Session`.

    session
        |> Session.insert "mode" "dark"

-}
insert : String -> String -> Session -> Session
insert key value (Session session) =
    session
        |> Dict.insert key (Persistent value)
        |> Session


{-| Retrieve a String value from the session for the given key (or `Nothing` if the key is not present).

    (session
        |> Session.get "mode"
        |> Maybe.withDefault "light"
    )
        == "dark"

-}
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


{-| Update the `Session`, given a `Maybe String` of the current value for the given key, and returning a `Maybe String`.

If you return `Nothing`, the key-value pair will be removed from the `Session` (or left out if it didn't exist in the first place).

    session
        |> Session.update "mode"
            (\mode ->
                case mode of
                    Just "dark" ->
                        Just "light"

                    Just "light" ->
                        Just "dark"

                    Nothing ->
                        Just "dark"
            )

-}
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


{-| Remove a key from the `Session`.
-}
remove : String -> Session -> Session
remove key (Session session) =
    session
        |> Dict.remove key
        |> Session


{-| An empty `Session` with no key-value pairs.
-}
empty : Session
empty =
    Session Dict.empty


{-| [`withSessionResult`](#withSessionResult) will return a `Result` with this type if it can't load a session.
-}
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


{-| The main function for using sessions. If you need more fine-grained control over cases where a session can't be loaded, see
[`withSessionResult`](#withSessionResult).
-}
withSession :
    { name : String
    , secrets : BackendTask error (List String)
    , options : Maybe SetCookie.Options
    }
    -> (Session -> BackendTask error ( Session, Response data errorPage ))
    -> Request
    -> BackendTask error (Response data errorPage)
withSession config toRequest request_ =
    request_
        |> withSessionResult config
            (\session ->
                session
                    |> Result.withDefault empty
                    |> toRequest
            )


{-| Same as `withSession`, but gives you an `Err` with the reason why the Session couldn't be loaded instead of
using `Session.empty` as a default in the cases where there is an error loading the session.

A session won't load if there is no session, or if it cannot be unsigned with your secrets. This could be because the cookie was tampered with
or otherwise corrupted, or because the cookie was signed with a secret that is no longer in the rotation.

-}
withSessionResult :
    { name : String
    , secrets : BackendTask error (List String)
    , options : Maybe SetCookie.Options
    }
    -> (Result NotLoadedReason Session -> BackendTask error ( Session, Response data errorPage ))
    -> Request
    -> BackendTask error (Response data errorPage)
withSessionResult config toTask request =
    let
        unsigned : BackendTask error (Result NotLoadedReason Session)
        unsigned =
            case Server.Request.cookie config.name request of
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
            (encodeSessionUpdate config toTask)


encodeSessionUpdate :
    { name : String
    , secrets : BackendTask error (List String)
    , options : Maybe SetCookie.Options
    }
    -> (d -> BackendTask error ( Session, Response data errorPage ))
    -> d
    -> BackendTask error (Response data errorPage)
encodeSessionUpdate config toRequest sessionResult =
    sessionResult
        |> toRequest
        |> BackendTask.andThen
            (\( sessionUpdate, response ) ->
                BackendTask.map
                    (\encoded ->
                        response
                            |> Server.Response.withSetCookieHeader
                                (SetCookie.setCookie config.name encoded (config.options |> Maybe.withDefault SetCookie.options))
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
