module Server.SetCookie exposing
    ( SetCookie
    , SameSite(..)
    , Options, initOptions
    , withImmediateExpiration, makeVisibleToJavaScript, nonSecure, setCookie, withDomain, withExpiration, withMaxAge, withPath, withSameSite
    , toString
    )

{-| Server-rendered pages in your `elm-pages` can set cookies. `elm-pages` provides two high-level ways to work with cookies:

  - [`Server.Session.withSession`](Server-Session#withSession)
  - [`Server.Response.withSetCookieHeader`](Server-Response#withSetCookieHeader)

[`Server.Session.withSession`](Server-Session#withSession) provides a high-level way to manage key-value pairs of data using cookie storage,
whereas `Server.Response.withSetCookieHeader` gives a more low-level tool for setting cookies. It's often best to use the
most high-level tool that will fit your use case.

You can learn more about the basics of cookies in the Web Platform in these helpful MDN documentation pages:

  - <https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie>
  - <https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies>

@docs SetCookie

@docs SameSite


## Options

@docs Options, initOptions

@docs withImmediateExpiration, makeVisibleToJavaScript, nonSecure, setCookie, withDomain, withExpiration, withMaxAge, withPath, withSameSite


## Internal

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
    , visibleToJavaScript : Bool
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


{-| Usually you'll want to use [`Server.Response.withSetCookieHeader`](Server-Response#withSetCookieHeader) instead.

This is a low-level helper that's there in case you want it but most users will never need this.

-}
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

        httpOnly : Bool
        httpOnly =
            not options.visibleToJavaScript
    in
    builder.name
        ++ "="
        ++ Url.percentEncode builder.value
        ++ option "Expires" (options.expiration |> Maybe.map Utc.fromTime)
        ++ option "Max-Age" (options.maxAge |> Maybe.map String.fromInt)
        ++ option "Path" options.path
        ++ option "Domain" options.domain
        ++ option "SameSite" (options.sameSite |> Maybe.map sameSiteToString)
        ++ boolOption "HttpOnly" httpOnly
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
    , visibleToJavaScript = False
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


{-| The default option in this API is for HttpOnly cookies <https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#httponly>.

Cookies can be exposed so you can read them from JavaScript using `Document.cookie`. When this is intended and understood
then there's nothing unsafe about that (for example, if you are setting a `darkMode` cookie and what to access that
dynamically). In this API you opt into exposing a cookie you set to JavaScript to ensure cookies aren't exposed to JS unintentionally.

In general if you can accomplish your goal using HttpOnly cookies (i.e. not using `makeVisibleToJavaScript`) then
it's a good practice. With server-rendered `elm-pages` applications you can often manage your session state by pulling
in session data from cookies in a `BackendTask` (which is resolved server-side before it ever reaches the browser).

-}
makeVisibleToJavaScript : Options -> Options
makeVisibleToJavaScript builder =
    { builder
        | visibleToJavaScript = True
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
