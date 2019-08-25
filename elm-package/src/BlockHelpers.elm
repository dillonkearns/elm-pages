module BlockHelpers exposing (imageSrc, route)

import Mark
import PagesNew


normalizedUrl url =
    url
        |> String.split "#"
        |> List.head
        |> Maybe.withDefault ""


route : Mark.Block String
route =
    Mark.string
        |> Mark.verify
            (\url ->
                let
                    validRoutes =
                        PagesNew.all |> List.map PagesNew.routeToString
                in
                if url |> String.startsWith "http" then
                    Ok url

                else if List.member (normalizedUrl url) validRoutes then
                    Ok url

                else
                    Err
                        { title = "Unknown relative URL " ++ url
                        , message =
                            [ url
                            , "\nMust be one of\n"
                            , String.join "\n" validRoutes
                            ]
                        }
            )


imageSrc : Mark.Block String
imageSrc =
    let
        imageAssets =
            PagesNew.allImages |> List.map PagesNew.imageUrl
    in
    Mark.string
        |> Mark.verify
            (\src ->
                let
                    fullSrc =
                        "/images/" ++ src
                in
                if fullSrc |> String.startsWith "http" then
                    Ok fullSrc

                else if List.member fullSrc imageAssets then
                    Ok fullSrc

                else
                    Err
                        { title = "Could not image `" ++ src ++ "`"
                        , message =
                            [ "Must be one of\n"
                            , imageAssets |> String.join "\n"
                            ]
                        }
            )
