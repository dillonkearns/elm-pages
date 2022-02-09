module Manifest exposing (handler)

import ApiRoute
import Cloudinary
import DataSource exposing (DataSource)
import Json.Encode
import MimeType
import Pages.Manifest as Manifest
import Pages.Url
import Route


handler : ApiRoute.ApiRoute ApiRoute.Response
handler =
    ApiRoute.succeed
        (manifest
            |> DataSource.map (manifestToFile canonicalUrl)
        )
        |> ApiRoute.literal "manifest.json"
        |> ApiRoute.single


manifestToFile : String -> Manifest.Config -> String
manifestToFile resolvedCanonicalUrl manifestConfig =
    manifestConfig
        |> Manifest.toJson resolvedCanonicalUrl
        |> (\manifestJsonValue ->
                Json.Encode.encode 0 manifestJsonValue
           )


manifest : DataSource Manifest.Config
manifest =
    Manifest.init
        { name = "elm-pages"
        , description = "elm-pages - " ++ tagline
        , startUrl = Route.Index |> Route.toPath
        , icons =
            [ icon webp 192
            , icon webp 512
            , icon MimeType.Png 192
            , icon MimeType.Png 512
            ]
        }
        |> Manifest.withShortName "elm-pages"
        |> DataSource.succeed


tagline : String
tagline =
    "pull in typed elm data to your pages"


webp : MimeType.MimeImage
webp =
    MimeType.OtherImage "webp"


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"


icon :
    MimeType.MimeImage
    -> Int
    -> Manifest.Icon
icon format width =
    { src = cloudinaryIcon format width
    , sizes = [ ( width, width ) ]
    , mimeType = format |> Just
    , purposes = [ Manifest.IconPurposeAny, Manifest.IconPurposeMaskable ]
    }


cloudinaryIcon :
    MimeType.MimeImage
    -> Int
    -> Pages.Url.Url
cloudinaryIcon mimeType width =
    Cloudinary.urlSquare "v1603234028/elm-pages/elm-pages-icon" (Just mimeType) width
