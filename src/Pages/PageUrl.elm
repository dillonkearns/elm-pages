module Pages.PageUrl exposing (PageUrl, toUrl)

{-|

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
