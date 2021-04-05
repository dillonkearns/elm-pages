module Site exposing (canonicalUrl, config, tagline)

import Cloudinary
import Color
import Head
import MimeType
import Pages exposing (images, pages)
import Pages.ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath exposing (PagePath)
import Pages.SiteConfig exposing (SiteConfig)
import Pages.StaticFile as StaticFile
import Pages.StaticHttp as StaticHttp


type alias StaticData =
    { siteName : String
    }


config : SiteConfig StaticData Pages.PathKey
config =
    { staticData = staticData
    , canonicalUrl = canonicalUrl
    , manifest = manifest
    , head = head
    }


staticData : StaticHttp.Request StaticData
staticData =
    StaticHttp.map StaticData
        (StaticFile.request "site-name.txt" StaticFile.body)


head : StaticData -> List (Head.Tag Pages.PathKey)
head static =
    [ Head.icon [ ( 32, 32 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 32)
    , Head.icon [ ( 16, 16 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 16)
    , Head.appleTouchIcon (Just 180) (cloudinaryIcon MimeType.Png 180)
    , Head.appleTouchIcon (Just 192) (cloudinaryIcon MimeType.Png 192)
    ]


canonicalUrl : StaticData -> String
canonicalUrl static =
    "https://elm-pages.com"


manifest : StaticData -> Manifest.Config Pages.PathKey
manifest static =
    { backgroundColor = Just Color.white
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - " ++ tagline
    , iarcRatingId = Nothing
    , name = static.siteName
    , themeColor = Just Color.white
    , startUrl = pages.index
    , shortName = Just "elm-pages"
    , sourceIcon = images.iconPng
    , icons =
        [ icon webp 192
        , icon webp 512
        , icon MimeType.Png 192
        , icon MimeType.Png 512
        ]
    }


tagline : String
tagline =
    "A statically typed site generator"


webp : MimeType.MimeImage
webp =
    MimeType.OtherImage "webp"


icon :
    MimeType.MimeImage
    -> Int
    -> Manifest.Icon pathKey
icon format width =
    { src = cloudinaryIcon format width
    , sizes = [ ( width, width ) ]
    , mimeType = format |> Just
    , purposes = [ Manifest.IconPurposeAny, Manifest.IconPurposeMaskable ]
    }


cloudinaryIcon :
    MimeType.MimeImage
    -> Int
    -> ImagePath pathKey
cloudinaryIcon mimeType width =
    Cloudinary.urlSquare "v1603234028/elm-pages/elm-pages-icon" (Just mimeType) width


socialIcon : ImagePath pathKey
socialIcon =
    Cloudinary.urlSquare "v1603234028/elm-pages/elm-pages-icon" Nothing 250
