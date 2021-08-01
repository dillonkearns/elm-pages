module Pages.PageUrl exposing (PageUrl, toUrl)

{-| Same as a Url in `elm/url`, but slightly more structured. The path portion of the URL is parsed into a [`Path`](Path) type, and
the query params use the [`QueryParams`](QueryParams) type which allows you to parse just the query params or access them into a Dict.

Because `elm-pages` takes care of the main routing for pages in your app, the standard Elm URL parser API isn't suited
to parsing query params individually, which is why the structure of these types is different.

@docs PageUrl, toUrl

-}

import Path exposing (Path)
import QueryParams exposing (QueryParams)
import Url


{-| -}
type alias PageUrl =
    { protocol : Url.Protocol
    , host : String
    , port_ : Maybe Int
    , path : Path
    , query : Maybe QueryParams
    , fragment : Maybe String
    }


{-| -}
toUrl : PageUrl -> Url.Url
toUrl url =
    { protocol = url.protocol
    , host = url.host
    , port_ = url.port_
    , path = url.path |> Path.toRelative
    , query = url.query |> Maybe.map QueryParams.toString
    , fragment = url.fragment
    }
