module Site exposing (config)

import ApiRoute
import Cloudinary
import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Json.Encode
import MimeType
import OptimizedDecoder as D
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath
import Route exposing (Route)
import Secrets
import SiteConfig exposing (SiteConfig)
import Sitemap


config : SiteConfig Data
config =
    \routes ->
        { data = data
        , canonicalUrl = canonicalUrl
        , manifest = manifest
        , head = head
        , apiRoutes = files routes
        }


files : List (Maybe Route) -> List (ApiRoute.Done ApiRoute.Response)
files allRoutes =
    [ ApiRoute.succeed
        (\userId ->
            DataSource.succeed
                { body =
                    Json.Encode.object
                        [ ( "id", Json.Encode.int (String.toInt userId |> Maybe.withDefault 0) )
                        , ( "name", Json.Encode.string ("Data for user " ++ userId) )
                        ]
                        |> Json.Encode.encode 2
                }
        )
        |> ApiRoute.literal "users"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.literal ".json"
        |> ApiRoute.buildTimeRoutes
            (\constructor ->
                DataSource.succeed
                    [ constructor "1"
                    , constructor "2"
                    , constructor "3"
                    ]
            )
    , ApiRoute.succeed
        (\repoName ->
            DataSource.Http.get
                (Secrets.succeed ("https://api.github.com/repos/dillonkearns/" ++ repoName))
                (D.field "stargazers_count" D.int)
                |> DataSource.map
                    (\stars ->
                        { body =
                            Json.Encode.object
                                [ ( "repo", Json.Encode.string repoName )
                                , ( "stars", Json.Encode.int stars )
                                ]
                                |> Json.Encode.encode 2
                        }
                    )
        )
        |> ApiRoute.literal "repo"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.literal ".json"
        |> ApiRoute.buildTimeRoutes
            (\constructor ->
                DataSource.succeed
                    [ constructor "elm-graphql"
                    ]
            )
    , ApiRoute.succeed
        (DataSource.succeed
            { body =
                allRoutes
                    |> List.filterMap identity
                    |> List.map
                        (\route ->
                            { path = Route.routeToPath (Just route) |> String.join "/"
                            , lastMod = Nothing
                            }
                        )
                    |> Sitemap.build { siteUrl = "https://elm-pages.com" }
            }
        )
        |> ApiRoute.literal "sitemap.xml"
        |> ApiRoute.singleRoute
    ]


type alias Data =
    { siteName : String
    }


data : DataSource.DataSource Data
data =
    DataSource.map Data
        --(StaticFile.request "site-name.txt" StaticFile.body)
        (DataSource.succeed "site-name")


head : Data -> List Head.Tag
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


manifest : Data -> Manifest.Config
manifest static =
    Manifest.init
        { name = static.siteName
        , description = "elm-pages - " ++ tagline
        , startUrl = PagePath.build []
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
