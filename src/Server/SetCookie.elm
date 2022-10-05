module Server.SetCookie exposing
    ( SetCookie
    , SameSite(..)
    , Options, initOptions
    , withImmediateExpiration, httpOnly, nonSecure, setCookie, withDomain, withExpiration, withMaxAge, withPath, withSameSite
    , toString
    )

{-| <https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie>

<https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies>

@docs SetCookie

@docs SameSite


## Options

@docs Options, initOptions

@docs withImmediateExpiration, httpOnly, nonSecure, setCookie, withDomain, withExpiration, withMaxAge, withPath, withSameSite

@docs toString

-}

import Time
import Url
import Utc


{-| -}
type alias SetCookie =
    { name : String
    , value : String
    , options : Options
    }


{-| -}
type alias Options =
    { expiration : Maybe Time.Posix
    , httpOnly : Bool
    , maxAge : Maybe Int
    , path : Maybe String
    , domain : Maybe String
    , secure : Bool
    , sameSite : Maybe SameSite
    }


{-| -}
type SameSite
    = Strict
    | Lax
    | None


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

        options : Options
        options =
            builder.options
    in
    builder.name
        ++ "="
        ++ Url.percentEncode builder.value
        ++ option "Expires" (options.expiration |> Maybe.map Utc.fromTime)
        ++ option "Max-Age" (options.maxAge |> Maybe.map String.fromInt)
        ++ option "Path" options.path
        ++ option "Domain" options.domain
        ++ option "SameSite" (options.sameSite |> Maybe.map sameSiteToString)
        ++ boolOption "HttpOnly" options.httpOnly
        ++ boolOption "Secure" options.secure


sameSiteToString : SameSite -> String
sameSiteToString sameSite =
    case sameSite of
        Strict ->
            "Strict"

        Lax ->
            "Lax"

        None ->
            "None"


{-| -}
setCookie : String -> String -> Options -> SetCookie
setCookie name value options =
    { name = name
    , value = value
    , options = options
    }


{-| -}
initOptions : Options
initOptions =
    { expiration = Nothing
    , httpOnly = False
    , maxAge = Nothing
    , path = Nothing
    , domain = Nothing
    , secure = True
    , sameSite = Nothing
    }


{-| -}
withExpiration : Time.Posix -> Options -> Options
withExpiration time builder =
    { builder
        | expiration = Just time
    }


{-| -}
withImmediateExpiration : Options -> Options
withImmediateExpiration builder =
    { builder
        | expiration = Just (Time.millisToPosix 0)
    }


{-| -}
httpOnly : Options -> Options
httpOnly builder =
    { builder
        | httpOnly = True
    }


{-| -}
withMaxAge : Int -> Options -> Options
withMaxAge maxAge builder =
    { builder
        | maxAge = Just maxAge
    }


{-| -}
withPath : String -> Options -> Options
withPath path builder =
    { builder
        | path = Just path
    }


{-| -}
withDomain : String -> Options -> Options
withDomain domain builder =
    { builder
        | domain = Just domain
    }


{-| Secure (only sent over https, or localhost on http) is the default. This overrides that and
removes the `Secure` attribute from the cookie.
-}
nonSecure : Options -> Options
nonSecure builder =
    { builder
        | secure = False
    }


{-| The default SameSite policy is Lax if one is not explicitly set. See the SameSite section in <https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#attributes>.
-}
withSameSite : SameSite -> Options -> Options
withSameSite sameSite builder =
    { builder
        | sameSite = Just sameSite
    }
