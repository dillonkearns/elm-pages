module Server.SetCookie exposing
    ( SetCookie, setCookie
    , Options, options
    , SameSite(..), withSameSite
    , withImmediateExpiration, makeVisibleToJavaScript, nonSecure, withDomain, withExpiration, withMaxAge, withPath, withoutPath
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

@docs SetCookie, setCookie


## Building Options

Usually you'll want to start by creating default `Options` with `options` and then overriding defaults using the `with...` helpers.

    import Server.SetCookie as SetCookie

    options : SetCookie.Options
    options =
        SetCookie.options
            |> SetCookie.nonSecure
            |> SetCookie.withMaxAge 123
            |> SetCookie.makeVisibleToJavaScript
            |> SetCookie.withoutPath
            |> SetCookie.setCookie "id" "a3fWa"

@docs Options, options

@docs SameSite, withSameSite

@docs withImmediateExpiration, makeVisibleToJavaScript, nonSecure, withDomain, withExpiration, withMaxAge, withPath, withoutPath


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


{-| The set of possible configuration options. You can configure this record directly, or use the `with...` helpers.
-}
type alias Options =
    { expiration : Maybe Time.Posix
    , visibleToJavaScript : Bool
    , maxAge : Maybe Int
    , path : Maybe String
    , domain : Maybe String
    , secure : Bool
    , sameSite : Maybe SameSite
    }


{-| Possible values for [the cookie's same-site value](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#samesitesamesite-value).

The default option is [`Lax`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#lax) (Lax does not send
cookies in cross-origin requests so it is a good default for most cases, but [`Strict`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#strict)
is even more restrictive).

Override the default option using [`withSameSite`](#withSameSite).

-}
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

        options_ : Options
        options_ =
            builder.options

        httpOnly : Bool
        httpOnly =
            not options_.visibleToJavaScript
    in
    builder.name
        ++ "="
        ++ Url.percentEncode builder.value
        ++ option "Expires" (options_.expiration |> Maybe.map Utc.fromTime)
        ++ option "Max-Age" (options_.maxAge |> Maybe.map String.fromInt)
        ++ option "Path" options_.path
        ++ option "Domain" options_.domain
        ++ option "SameSite" (options_.sameSite |> Maybe.map sameSiteToString)
        ++ boolOption "HttpOnly" httpOnly
        ++ boolOption "Secure" options_.secure


sameSiteToString : SameSite -> String
sameSiteToString sameSite =
    case sameSite of
        Strict ->
            "Strict"

        Lax ->
            "Lax"

        None ->
            "None"


{-| Create a `SetCookie` record with the given name, value, and [`Options`](Options]. To add a `Set-Cookie` header, you can
pass this value with [`Server.Response.withSetCookieHeader`](Server-Response#withSetCookieHeader). Or for more low-level
uses you can stringify the value manually with [`toString`](#toString).
-}
setCookie : String -> String -> Options -> SetCookie
setCookie name value options_ =
    { name = name
    , value = value
    , options = options_
    }


{-| Initialize the default `SetCookie` `Options`. Can be configured directly through a record update, or with `withExpiration`, etc.
-}
options : Options
options =
    { expiration = Nothing
    , visibleToJavaScript = False
    , maxAge = Nothing
    , path = Just "/"
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


{-| Sets [`Expires`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#expiresdate) to `Time.millisToPosix 0`,
which effectively tells the browser to delete the cookie immediately (by giving it an expiration date in the past).
-}
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


{-| Sets the `Set-Cookie`'s [`Max-Age`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#max-agenumber).
-}
withMaxAge : Int -> Options -> Options
withMaxAge maxAge builder =
    { builder
        | maxAge = Just maxAge
    }


{-| Sets the `Set-Cookie`'s [`Path`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#pathpath-value).

The default value is `/`, which will match any sub-directories or the root directory. See also [\`withoutPath](#withoutPath)

-}
withPath : String -> Options -> Options
withPath path builder =
    { builder
        | path = Just path
    }


{-|

> If the server omits the Path attribute, the user agent will use the "directory" of the request-uri's path component as the default value.

Source: <https://www.rfc-editor.org/rfc/rfc6265>. See <https://stackoverflow.com/a/43336097>.

-}
withoutPath : Options -> Options
withoutPath builder =
    { builder
        | path = Nothing
    }


{-| Sets the `Set-Cookie`'s [`Domain`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#domaindomain-value).
-}
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
