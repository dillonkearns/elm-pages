module Server.SetCookie exposing
    ( withImmediateExpiration
    , SameSite(..), SetCookie, httpOnly, nonSecure, setCookie, toString, withDomain, withExpiration, withMaxAge, withPath, withSameSite
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
    , sameSite : Maybe SameSite
    }


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
    in
    builder.name
        ++ "="
        ++ Url.percentEncode builder.value
        ++ option "Expires" (builder.expiration |> Maybe.map Utc.fromTime)
        ++ option "Max-Age" (builder.maxAge |> Maybe.map String.fromInt)
        ++ option "Path" builder.path
        ++ option "Domain" builder.domain
        ++ option "SameSite" (builder.sameSite |> Maybe.map sameSiteToString)
        ++ boolOption "HttpOnly" builder.httpOnly
        ++ boolOption "Secure" builder.secure


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
    , sameSite = Nothing
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


{-| The default SameSite policy is Lax if one is not explicitly set. See the SameSite section in <https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#attributes>.
-}
withSameSite : SameSite -> SetCookie -> SetCookie
withSameSite sameSite builder =
    { builder
        | sameSite = Just sameSite
    }
