module Site exposing (config)

import BackendTask exposing (BackendTask)
import Cloudinary
import Exception exposing (Throwable)
import Head
import MimeType
import Pages.Manifest as Manifest
import Pages.Url
import Route exposing (Route)
import SiteConfig exposing (SiteConfig)


config : SiteConfig
config =
    { canonicalUrl = canonicalUrl
    , head = head
    }


type alias Data =
    { siteName : String
    }


data : BackendTask Throwable Data
data =
    BackendTask.map Data
        --(StaticFile.request "site-name.txt" StaticFile.body)
        (BackendTask.succeed "site-name")


head : BackendTask Throwable (List Head.Tag)
head =
    [ Head.icon [ ( 32, 32 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 32)
    , Head.icon [ ( 16, 16 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 16)
    , Head.appleTouchIcon (Just 180) (cloudinaryIcon MimeType.Png 180)
    , Head.appleTouchIcon (Just 192) (cloudinaryIcon MimeType.Png 192)
    , Head.sitemapLink "/sitemap.xml"
    ]
        |> BackendTask.succeed


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"


manifest : Data -> Manifest.Config
manifest static =
    Manifest.init
        { name = static.siteName
        , description = "elm-pages - " ++ tagline
        , startUrl = Route.Slide__Number_ { number = "1" } |> Route.toPath
        , icons =
            [ icon webp 192
            , icon webp 512
            , icon MimeType.Png 192
            , icon MimeType.Png 512
            ]
        }
        |> Manifest.withShortName "elm-pages"


tagline : String
tagline =
    "A statically typed site generator"


webp : MimeType.MimeImage
webp =
    MimeType.OtherImage "webp"


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
