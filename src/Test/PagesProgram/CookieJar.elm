module Test.PagesProgram.CookieJar exposing
    ( CookieJar
    , init, set, setSession, get, toDict
    , withSetCookieHeaders
    , withCookies
    )

{-| A cookie jar used to seed the initial request of a test and to track
cookies across subsequent requests. Supports:

  - Setting/getting individual cookies
  - Seeding a signed session cookie via [`setSession`](#setSession)
  - Parsing `Set-Cookie` response headers to capture cookies across requests
  - Applying the jar to a [`Test.BackendTask.TestSetup`](Test-BackendTask#TestSetup)
    via [`withCookies`](#withCookies)

@docs CookieJar


## Building

@docs init, set, setSession, get, toDict


## Capturing from responses

@docs withSetCookieHeaders


## Seeding a test

@docs withCookies

-}

import Dict exposing (Dict)
import Test.BackendTask.Internal as TestInternal
import Test.PagesProgram.Session exposing (Session)
import Url


{-| A collection of cookies maintained across HTTP requests.
-}
type CookieJar
    = CookieJar (Dict String String)


{-| An empty cookie jar, ready for [`set`](#set) and
[`setSession`](#setSession).
-}
init : CookieJar
init =
    CookieJar Dict.empty


{-| Set a cookie in the jar.
-}
set : String -> String -> CookieJar -> CookieJar
set name value (CookieJar cookies) =
    CookieJar (Dict.insert name value cookies)


{-| Set a signed session cookie in the jar. The [`Session`](Test-PagesProgram-Session#Session)
value is encoded and signed the same way
[`Server.Session`](Server-Session) encodes its payload at runtime, so routes
reading the cookie get the seeded values back out.

    import Test.PagesProgram.CookieJar as CookieJar
    import Test.PagesProgram.Session as Session

    CookieJar.init
        |> CookieJar.setSession "mysession"
            (Session.init
                |> Session.withValue "userId" "42"
            )

-}
setSession : String -> Session -> CookieJar -> CookieJar
setSession name sessionValue jar =
    set name (TestInternal.mockSignValue (TestInternal.encodeSession sessionValue)) jar


{-| Get a cookie from the jar.
-}
get : String -> CookieJar -> Maybe String
get name (CookieJar cookies) =
    Dict.get name cookies


{-| Convert the cookie jar to a Dict for use in request construction.
-}
toDict : CookieJar -> Dict String String
toDict (CookieJar cookies) =
    cookies


{-| Apply a list of Set-Cookie header values to the cookie jar.
Parses each header to extract the cookie name and value, ignoring
attributes like Path, Domain, HttpOnly, etc.

    CookieJar.init
        |> CookieJar.withSetCookieHeaders
            [ "session=abc123; Path=/; HttpOnly"
            , "theme=dark"
            ]
        |> CookieJar.get "session"
        -- Just "abc123"

-}
withSetCookieHeaders : List String -> CookieJar -> CookieJar
withSetCookieHeaders headers jar =
    List.foldl applyOneSetCookie jar headers


applyOneSetCookie : String -> CookieJar -> CookieJar
applyOneSetCookie header jar =
    -- Set-Cookie format: "name=value; Path=/; HttpOnly; ..."
    -- We only care about the first key=value pair (before the first semicolon with attributes)
    case String.split ";" header of
        [] ->
            jar

        nameValuePart :: _ ->
            case String.split "=" (String.trim nameValuePart) of
                name :: valueParts ->
                    let
                        cookieName : String
                        cookieName =
                            String.trim name
                    in
                    if String.isEmpty cookieName || isCookieAttribute cookieName then
                        jar

                    else
                        let
                            cookieValue : String
                            cookieValue =
                                String.join "=" valueParts
                                    |> String.trim
                                    |> (\v -> Url.percentDecode v |> Maybe.withDefault v)
                        in
                        set cookieName cookieValue jar

                _ ->
                    jar


{-| Check if a name is a known Set-Cookie attribute rather than a cookie name.
-}
isCookieAttribute : String -> Bool
isCookieAttribute name =
    List.member (String.toLower name)
        [ "path", "domain", "expires", "max-age", "secure", "httponly", "samesite" ]


{-| Apply the jar to a [`Test.BackendTask.TestSetup`](Test-BackendTask#TestSetup),
seeding every cookie in the jar on the initial request.

    import Test.BackendTask as BackendTaskTest
    import Test.PagesProgram.CookieJar as CookieJar

    BackendTaskTest.init
        |> CookieJar.withCookies
            (CookieJar.init
                |> CookieJar.set "theme" "dark"
            )

-}
withCookies : CookieJar -> TestInternal.TestSetup -> TestInternal.TestSetup
withCookies (CookieJar cookies) setup =
    Dict.foldl TestInternal.withRequestCookie setup cookies
