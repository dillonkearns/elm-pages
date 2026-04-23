module Test.PagesProgram.CookieJar exposing
    ( CookieJar
    , CookieEntry
    , init, set, setSession, get, getEntry, toDict, entries
    , withSetCookieHeaders
    , withCookies
    )

{-| A cookie jar used to seed the initial request of a test and to track
cookies across subsequent requests. Supports:

  - Setting/getting individual cookies
  - Seeding a signed session cookie via [`setSession`](#setSession)
  - Parsing `Set-Cookie` response headers to capture cookies and their
    attributes (Path, Domain, Expires, Max-Age, Secure, HttpOnly, SameSite)
    across requests
  - Applying the jar to a [`Test.BackendTask.TestSetup`](Test-BackendTask#TestSetup)
    via [`withCookies`](#withCookies)

@docs CookieJar
@docs CookieEntry


## Building

@docs init, set, setSession, get, getEntry, toDict, entries


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
    = CookieJar (Dict String CookieEntry)


{-| A cookie with its value and attributes as parsed from `Set-Cookie`.

Attributes default to unset/false when a cookie is added via [`set`](#set) or
[`setSession`](#setSession). [`withSetCookieHeaders`](#withSetCookieHeaders)
populates attributes from response headers.

`expires` is preserved as the raw header string (date formats vary). `sameSite`
is the raw attribute value (`"Strict"`, `"Lax"`, or `"None"`).

-}
type alias CookieEntry =
    { value : String
    , path : Maybe String
    , domain : Maybe String
    , expires : Maybe String
    , maxAge : Maybe Int
    , secure : Bool
    , httpOnly : Bool
    , sameSite : Maybe String
    }


defaultEntry : String -> CookieEntry
defaultEntry value =
    { value = value
    , path = Nothing
    , domain = Nothing
    , expires = Nothing
    , maxAge = Nothing
    , secure = False
    , httpOnly = False
    , sameSite = Nothing
    }


{-| An empty cookie jar, ready for [`set`](#set) and
[`setSession`](#setSession).
-}
init : CookieJar
init =
    CookieJar Dict.empty


{-| Set a cookie in the jar with the given name and value. Attributes default
to unset/false; use [`withSetCookieHeaders`](#withSetCookieHeaders) to capture
attributes from a response.
-}
set : String -> String -> CookieJar -> CookieJar
set name value (CookieJar cookies) =
    CookieJar (Dict.insert name (defaultEntry value) cookies)


{-| Set a signed session cookie in the jar. The [`Session`](Test-PagesProgram-Session#Session)
value is encoded and signed the same way
[`Server.Session`](Server-Session) encodes its payload at runtime, so routes
reading the cookie get the seeded values back out.

    import Test.PagesProgram.CookieJar as CookieJar
    import Test.PagesProgram.Session as Session

    CookieJar.init
        |> CookieJar.setSession
            { name = "mysession"
            , secret = "test-secret"
            , session =
                Session.init
                    |> Session.withValue "userId" "42"
            }

The `secret` is recorded alongside the signed cookie so the visual test
runner can surface which secret produced each signed cookie. The test mock
does not use real HMAC, so `secret` may be any non-empty string **without `.`
characters**.

-}
setSession : { name : String, secret : String, session : Session } -> CookieJar -> CookieJar
setSession config jar =
    set config.name (TestInternal.mockSignValue config.secret (TestInternal.encodeSession config.session)) jar


{-| Get a cookie's value from the jar.
-}
get : String -> CookieJar -> Maybe String
get name (CookieJar cookies) =
    Dict.get name cookies |> Maybe.map .value


{-| Get a cookie's full entry (value + attributes) from the jar.
-}
getEntry : String -> CookieJar -> Maybe CookieEntry
getEntry name (CookieJar cookies) =
    Dict.get name cookies


{-| Convert the cookie jar to a Dict of name/value pairs for use in request
construction. Attributes are dropped — requests only need name/value.
-}
toDict : CookieJar -> Dict String String
toDict (CookieJar cookies) =
    Dict.map (\_ entry -> entry.value) cookies


{-| List every cookie in the jar with its full entry.
-}
entries : CookieJar -> List ( String, CookieEntry )
entries (CookieJar cookies) =
    Dict.toList cookies


{-| Apply a list of Set-Cookie header values to the cookie jar. Parses each
header to extract the cookie name, value, and attributes (`Path`, `Domain`,
`Expires`, `Max-Age`, `Secure`, `HttpOnly`, `SameSite`). Unknown attributes
are ignored.

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
applyOneSetCookie header (CookieJar cookies) =
    -- Set-Cookie format: "name=value; Attr1=v1; Attr2; ..."
    case String.split ";" header of
        [] ->
            CookieJar cookies

        nameValuePart :: attrParts ->
            case splitFirstEquals (String.trim nameValuePart) of
                Just ( name, rawValue ) ->
                    let
                        cookieName : String
                        cookieName =
                            String.trim name
                    in
                    if String.isEmpty cookieName || isReservedAttributeName cookieName then
                        CookieJar cookies

                    else
                        let
                            cookieValue : String
                            cookieValue =
                                rawValue
                                    |> String.trim
                                    |> (\v -> Url.percentDecode v |> Maybe.withDefault v)

                            entry : CookieEntry
                            entry =
                                attrParts
                                    |> List.foldl applyAttribute (defaultEntry cookieValue)
                        in
                        CookieJar (Dict.insert cookieName entry cookies)

                Nothing ->
                    CookieJar cookies


applyAttribute : String -> CookieEntry -> CookieEntry
applyAttribute segment entry =
    let
        ( rawName, rawValue ) =
            case splitFirstEquals (String.trim segment) of
                Just ( n, v ) ->
                    ( String.trim n, Just (String.trim v) )

                Nothing ->
                    ( String.trim segment, Nothing )

        attrName : String
        attrName =
            String.toLower rawName
    in
    case ( attrName, rawValue ) of
        ( "path", Just value ) ->
            { entry | path = Just value }

        ( "domain", Just value ) ->
            { entry | domain = Just value }

        ( "expires", Just value ) ->
            { entry | expires = Just value }

        ( "max-age", Just value ) ->
            case String.toInt value of
                Just n ->
                    { entry | maxAge = Just n }

                Nothing ->
                    entry

        ( "samesite", Just value ) ->
            { entry | sameSite = Just value }

        ( "secure", _ ) ->
            { entry | secure = True }

        ( "httponly", _ ) ->
            { entry | httpOnly = True }

        _ ->
            entry


{-| First `=` splits a "name=value" pair. Subsequent `=` characters remain in
the value — important for base64-ish signatures and JSON-in-cookies.
-}
splitFirstEquals : String -> Maybe ( String, String )
splitFirstEquals input =
    case String.indexes "=" input |> List.head of
        Just idx ->
            Just ( String.left idx input, String.dropLeft (idx + 1) input )

        Nothing ->
            Nothing


{-| A safety net for reserved attribute names showing up where the cookie's
own name would be — e.g. a malformed header like `"Path=/; HttpOnly"` without
a preceding cookie pair. Treat those as noise.
-}
isReservedAttributeName : String -> Bool
isReservedAttributeName name =
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
    Dict.foldl (\name entry -> TestInternal.withRequestCookie name entry.value) setup cookies
