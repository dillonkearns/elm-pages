module Pages.PageUrl exposing
    ( PageUrl, toUrl
    , parseQueryParams
    )

{-| Same as a Url in `elm/url`, but slightly more structured. The path portion of the URL is parsed into a `List String` representing each segment, and
the query params are parsed into a `Dict String (List String)`.

@docs PageUrl, toUrl

@docs parseQueryParams

-}

import Dict exposing (Dict)
import QueryParams
import Url
import UrlPath exposing (UrlPath)


{-| -}
type alias PageUrl =
    { protocol : Url.Protocol
    , host : String
    , port_ : Maybe Int
    , path : UrlPath
    , query : Dict String (List String)
    , fragment : Maybe String
    }


{-| -}
toUrl : PageUrl -> Url.Url
toUrl url =
    { protocol = url.protocol
    , host = url.host
    , port_ = url.port_
    , path = url.path |> UrlPath.toRelative
    , query =
        if url.query |> Dict.isEmpty then
            Nothing

        else
            url.query |> QueryParams.toString |> Just
    , fragment = url.fragment
    }


{-| -}
parseQueryParams : String -> Dict String (List String)
parseQueryParams =
    QueryParams.fromString
