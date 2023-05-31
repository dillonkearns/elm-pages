module Url.Extra exposing (resolve)

{-| TODO: this module should implement the algorithm described at
<https://url.spec.whatwg.org/>
-}

import Url exposing (Url)


{-| This resolves a URL string (either an absolute or relative URL) against a base URL (given as a `Location`).
-}
resolve : Url -> String -> Url
resolve base url =
    Url.fromString url
        -- TODO: implement correct logic (current logic is only correct for "authority-relative" URLs without query or fragment strings)
        |> Maybe.withDefault
            { base
                | path =
                    if String.startsWith "/" url then
                        url

                    else
                        String.split "/" base.path
                            |> List.reverse
                            |> List.drop 1
                            |> List.reverse
                            |> (\l -> l ++ String.split "/" url)
                            |> String.join "/"
                , query = Nothing
                , fragment = Nothing
            }
