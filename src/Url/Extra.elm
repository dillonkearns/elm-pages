module Url.Extra exposing (resolve, toUrlRequest)

{-| TODO: this module should implement the algorithm described at
<https://url.spec.whatwg.org/>
-}

import Browser
import Url exposing (Protocol(..), Url)


{-| This resolves a URL string (either an absolute or relative URL) against a base URL (given as a `Location`).
-}
resolve : Url -> String -> Url
resolve base url =
    -- TODO: This passes all the tests (except one), but could probably be nicer.
    case Url.fromString url of
        Just newUrl ->
            newUrl

        Nothing ->
            (if String.isEmpty url then
                base

             else if String.startsWith "#" url then
                { base | fragment = Just (String.dropLeft 1 url) }

             else if String.startsWith "?" url then
                { base
                    | query = Just (String.dropLeft 1 url)
                    , fragment = Nothing
                }

             else if String.startsWith "//" url then
                { base | host = String.dropLeft 2 url, path = "", fragment = Nothing, query = Nothing }

             else
                { base
                    | path =
                        if String.startsWith "/" url then
                            url

                        else if url == ".." || String.startsWith "../" url then
                            String.split "/" base.path
                                |> List.reverse
                                |> List.drop 1
                                |> parseDoubleDots url

                        else
                            String.split "/" base.path
                                |> List.reverse
                                |> List.drop 1
                                |> List.reverse
                                |> (\l ->
                                        l
                                            ++ String.split "/"
                                                (if String.startsWith "./" url then
                                                    String.dropLeft 2 url

                                                 else if String.startsWith "." url then
                                                    String.dropLeft 1 url

                                                 else
                                                    url
                                                )
                                   )
                                |> String.join "/"
                    , fragment = Nothing
                    , query = Nothing
                }
            )
                |> (\u ->
                        -- pass back through Url.fromString just to get the query and fragment in the right place
                        Url.toString u
                            |> Url.fromString
                            |> Maybe.withDefault u
                   )


parseDoubleDots : String -> List String -> String
parseDoubleDots url pathSegments =
    if String.startsWith "../" url then
        parseDoubleDots (String.dropLeft 3 url) (List.drop 1 pathSegments)

    else if String.startsWith ".." url then
        parseDoubleDots (String.dropLeft 2 url) (List.drop 1 pathSegments)

    else
        String.join "/" (List.reverse pathSegments) ++ "/" ++ url


toUrlRequest : Url -> String -> Browser.UrlRequest
toUrlRequest base href =
    resolve base href
        |> (\url ->
                if url.protocol == base.protocol && url.host == base.host && url.port_ == base.port_ then
                    Browser.Internal url

                else
                    Browser.External href
           )
