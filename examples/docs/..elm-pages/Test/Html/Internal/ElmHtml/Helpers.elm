module Test.Html.Internal.ElmHtml.Helpers exposing (filterKnownKeys)

{-| Internal helpers for ElmHtml

@docs filterKnownKeys

-}

import Dict exposing (Dict)
import Test.Html.Internal.ElmHtml.Constants exposing (knownKeys)


{-| Filter out keys that we don't know
-}
filterKnownKeys : Dict String a -> Dict String a
filterKnownKeys =
    Dict.filter (\key _ -> not (List.member key knownKeys))
