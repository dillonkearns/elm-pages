module Site exposing (config)

import Cloudinary
import DataSource exposing (DataSource)
import Head
import MimeType
import Pages.Url
import SiteConfig exposing (SiteConfig)


config : SiteConfig Data
config =
    { data = data
    , canonicalUrl = canonicalUrl
    , head = head
    }


type alias Data =
    String


data : DataSource.DataSource Data
data =
    --DataSource.File.rawFile "hello.txt"
    DataSource.succeed "hello"


head : Data -> List Head.Tag
head static =
    [ Head.icon [ ( 32, 32 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 32)
    , Head.icon [ ( 16, 16 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 16)
    , Head.appleTouchIcon (Just 180) (cloudinaryIcon MimeType.Png 180)
    , Head.appleTouchIcon (Just 192) (cloudinaryIcon MimeType.Png 192)
    , Head.rssLink "/blog/feed.xml"
    , Head.sitemapLink "/sitemap.xml"
    , Head.manifestLink "manifest.json"
    ]


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"


tagline : String
tagline =
    "pull in typed elm data to your pages"


cloudinaryIcon :
    MimeType.MimeImage
    -> Int
    -> Pages.Url.Url
cloudinaryIcon mimeType width =
    Cloudinary.urlSquare "v1603234028/elm-pages/elm-pages-icon" (Just mimeType) width
