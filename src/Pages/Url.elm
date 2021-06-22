module Pages.Url exposing (Url, external, fromPath, toAbsoluteUrl, toString)

{-| Some of the `elm-pages` APIs will take internal URLs and ensure that they have the `canonicalSiteUrl` prepended.

That's the purpose for this type. If you have an external URL, like `Pages.Url.external "https://google.com"`,
then the canonicalUrl will not be prepended when it is used in a head tag.

If you refer to a local page, like `Route.Index |> Route.toPath |> Pages.Url.fromPath`, or `Pages.Url.fromPath`

@docs Url, external, fromPath, toAbsoluteUrl, toString

-}

import Pages.Internal.String as String
import Path exposing (Path)


{-| -}
type Url
    = Internal String
    | External String


{-| -}
fromPath : Path -> Url
fromPath path =
    path |> Path.toAbsolute |> Internal


{-| -}
external : String -> Url
external externalUrl =
    External externalUrl


{-| -}
toString : Url -> String
toString path =
    case path of
        Internal rawPath ->
            rawPath

        External url ->
            url


{-| -}
toAbsoluteUrl : String -> Url -> String
toAbsoluteUrl canonicalSiteUrl url =
    case url of
        External externalUrl ->
            externalUrl

        Internal internalUrl ->
            join canonicalSiteUrl internalUrl


join : String -> String -> String
join base path =
    String.chopEnd "/" base ++ "/" ++ String.chopStart "/" path
