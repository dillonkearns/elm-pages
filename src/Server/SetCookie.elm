module Server.SetCookie exposing
    ( withImmediateExpiration
    , SetCookie, httpOnly, nonSecure, setCookie, toString, withDomain, withExpiration, withMaxAge, withPath
    )

{-| <https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie>

<https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies>

@docs withImmediateExpiration

-}

import Time
import Url
import Utc


{-| -}
type alias SetCookie =
    { name : String
    , value : String
    , expiration : Maybe Time.Posix
    , httpOnly : Bool
    , maxAge : Maybe Int
    , path : Maybe String
    , domain : Maybe String
    , secure : Bool
    }


{-| -}
toString : SetCookie -> String
toString builder =
    let
        option : String -> Maybe String -> String
        option name maybeValue =
            case maybeValue of
                Just value ->
                    "; " ++ name ++ "=" ++ value

                Nothing ->
                    ""

        boolOption : String -> Bool -> String
        boolOption name bool =
            if bool then
                "; " ++ name

            else
                ""
    in
    builder.name
        ++ "="
        ++ Url.percentEncode builder.value
        ++ option "Expires" (builder.expiration |> Maybe.map Utc.fromTime)
        ++ option "Max-Age" (builder.maxAge |> Maybe.map String.fromInt)
        ++ option "Path" builder.path
        ++ option "Domain" builder.domain
        ++ boolOption "HttpOnly" builder.httpOnly
        ++ boolOption "Secure" builder.secure


{-| -}
setCookie : String -> String -> SetCookie
setCookie name value =
    { name = name
    , value = value
    , expiration = Nothing
    , httpOnly = False
    , maxAge = Nothing
    , path = Nothing
    , domain = Nothing
    , secure = True
    }


{-| -}
withExpiration : Time.Posix -> SetCookie -> SetCookie
withExpiration time builder =
    { builder
        | expiration = Just time
    }


{-| -}
withImmediateExpiration : SetCookie -> SetCookie
withImmediateExpiration builder =
    { builder
        | expiration = Just (Time.millisToPosix 0)
    }


{-| -}
httpOnly : SetCookie -> SetCookie
httpOnly builder =
    { builder
        | httpOnly = True
    }


withMaxAge : Int -> SetCookie -> SetCookie
withMaxAge maxAge builder =
    { builder
        | maxAge = Just maxAge
    }


withPath : String -> SetCookie -> SetCookie
withPath path builder =
    { builder
        | path = Just path
    }


withDomain : String -> SetCookie -> SetCookie
withDomain domain builder =
    { builder
        | domain = Just domain
    }


{-| Secure (only sent over https, or localhost on http) is the default. This overrides that and
removes the `Secure` attribute from the cookie.
-}
nonSecure : SetCookie -> SetCookie
nonSecure builder =
    { builder
        | secure = False
    }
