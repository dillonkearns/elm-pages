module Site exposing (config)

import Cloudinary
import Color
import Head
import Json.Encode
import MimeType
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath as PagePath
import Pages.StaticHttp as StaticHttp
import Route exposing (Route)
import SiteConfig exposing (SiteConfig)
import Sitemap


config : SiteConfig StaticData
config =
    \routes ->
        { staticData = staticData
        , canonicalUrl = canonicalUrl
        , manifest = manifest
        , head = head
        , generateFiles = generateFiles routes
        }



-- TODO wire this in as part of the config


generateFiles :
    List (Maybe Route)
    ->
        StaticHttp.Request
            (List
                (Result
                    String
                    { path : List String
                    , content : String
                    }
                )
            )
generateFiles allRoutes =
    StaticHttp.succeed
        [ siteMap allRoutes |> Ok
        ]


type alias StaticData =
    { siteName : String
    }


staticData : StaticHttp.Request StaticData
staticData =
    StaticHttp.map StaticData
        --(StaticFile.request "site-name.txt" StaticFile.body)
        (StaticHttp.succeed "site-name")


head : StaticData -> List Head.Tag
head static =
    [ Head.icon [ ( 32, 32 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 32)
    , Head.icon [ ( 16, 16 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 16)
    , Head.appleTouchIcon (Just 180) (cloudinaryIcon MimeType.Png 180)
    , Head.appleTouchIcon (Just 192) (cloudinaryIcon MimeType.Png 192)
    , Head.sitemapLink "/sitemap.xml"
    ]


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"


manifest : StaticData -> Manifest.Config
manifest static =
    { backgroundColor = Just Color.white
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - " ++ tagline
    , iarcRatingId = Nothing
    , name = static.siteName
    , themeColor = Just Color.white
    , startUrl = PagePath.build []
    , shortName = Just "elm-pages"
    , sourceIcon = ImagePath.build [ "images", "icon-png.png" ]
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
    -> ImagePath
cloudinaryIcon mimeType width =
    Cloudinary.urlSquare "v1603234028/elm-pages/elm-pages-icon" (Just mimeType) width


siteMap :
    List (Maybe Route)
    -> { path : List String, content : String }
siteMap allRoutes =
    allRoutes
        |> List.filterMap identity
        |> List.map
            (\route ->
                { path = Route.routeToPath (Just route) |> String.join "/"
                , lastMod = Nothing
                }
            )
        |> Sitemap.build { siteUrl = "https://elm-pages.com" }
        |> (\sitemapXmlString -> { path = [ "sitemap.xml" ], content = sitemapXmlString })
