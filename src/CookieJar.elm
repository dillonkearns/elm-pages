module CookieJar exposing
    ( CookieJar
    , empty, set, get, toDict
    , applySetCookieHeaders
    )

{-| A simple cookie jar that tracks cookies across requests in the test framework.

Supports:

  - Setting/getting individual cookies
  - Parsing `Set-Cookie` response headers to capture cookies
  - Converting to a `Dict String String` for request construction

@docs CookieJar

@docs empty, set, get, toDict

@docs applySetCookieHeaders

-}

import Dict exposing (Dict)
import Url


{-| A collection of cookies maintained across HTTP requests.
-}
type CookieJar
    = CookieJar (Dict String String)


{-| An empty cookie jar.
-}
empty : CookieJar
empty =
    CookieJar Dict.empty


{-| Set a cookie in the jar.
-}
set : String -> String -> CookieJar -> CookieJar
set name value (CookieJar cookies) =
    CookieJar (Dict.insert name value cookies)


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

    CookieJar.empty
        |> CookieJar.applySetCookieHeaders
            [ "session=abc123; Path=/; HttpOnly"
            , "theme=dark"
            ]
        |> CookieJar.get "session"
        -- Just "abc123"

-}
applySetCookieHeaders : List String -> CookieJar -> CookieJar
applySetCookieHeaders headers jar =
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
                        cookieName =
                            String.trim name

                        cookieValue =
                            String.join "=" valueParts
                                |> String.trim
                                |> (\v -> Url.percentDecode v |> Maybe.withDefault v)
                    in
                    if String.isEmpty cookieName then
                        jar

                    else
                        set cookieName cookieValue jar

                _ ->
                    jar
