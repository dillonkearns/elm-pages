module Pages.ContentCache exposing
    ( ContentCache
    , ContentJson
    , Entry(..)
    , Path
    , init
    , pathForUrl
    )

import Dict exposing (Dict)
import Pages.Internal.NotFoundReason
import Pages.Internal.String as String
import RequestsAndPending exposing (RequestsAndPending)
import Url exposing (Url)


type alias ContentCache =
    Dict Path Entry


type Entry
    = Parsed


type alias Path =
    List String


init :
    Maybe ( Path, ContentJson )
    -> ContentCache
init maybeInitialPageContent =
    case maybeInitialPageContent of
        Nothing ->
            Dict.empty

        Just ( urls, _ ) ->
            Dict.singleton urls Parsed


type alias ContentJson =
    { staticData : RequestsAndPending
    , is404 : Bool
    , path : Maybe String
    , notFoundReason : Maybe Pages.Internal.NotFoundReason.Payload
    }


pathForUrl : { currentUrl : Url, basePath : List String } -> Path
pathForUrl { currentUrl, basePath } =
    currentUrl.path
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")
        |> List.drop (List.length basePath)
