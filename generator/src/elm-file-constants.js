const exposingList =
  "(application, PageRoute, all, pages, routeToString, Image, imageUrl, images, allImages, isValidRoute)";

function staticRouteStuff(staticRoutes) {
  return `

type PageRoute = PageRoute (List String)

type Image = Image (List String)

imageUrl : Image -> String
imageUrl (Image path) =
    "/"
        ++ String.join "/" ("images" :: path)

${staticRoutes.allRoutes}

${staticRoutes.routeRecord}

${staticRoutes.urlParser}

${staticRoutes.imageAssetsRecord}

allImages : List Image
allImages =
    [${staticRoutes.allImages.join("\n    , ")}
    ]

routeToString : PageRoute -> String
routeToString (PageRoute route) =
    "/"
      ++ (route |> String.join "/")


isValidRoute : String -> Result String ()
isValidRoute route =
    let
        validRoutes =
            List.map routeToString all
    in
    if
        (route |> String.startsWith "http://")
            || (route |> String.startsWith "https://")
            || (validRoutes |> List.member route)
    then
        Ok ()

    else
        ("Valid routes:\\n"
            ++ String.join "\\n\\n" validRoutes
        )
            |> Err
`;
}

function elmPagesUiFile(staticRoutes) {
  return `port module PagesNew exposing ${exposingList}

import Dict exposing (Dict)
import Color exposing (Color)
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages
import Pages.ContentCache exposing (Page)
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import RawContent
import Url.Parser as Url exposing ((</>), s)
import Pages.Document


port toJsPort : Json.Encode.Value -> Cmd msg


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , head : metadata -> List Head.Tag
    , documents : List (Pages.Document.DocumentParser metadata view)
    , manifest :
        { backgroundColor : Maybe Color
        , categories : List Category
        , displayMode : DisplayMode
        , orientation : Orientation
        , description : String
        , iarcRatingId : Maybe String
        , name : String
        , themeColor : Maybe Color
        , startUrl : PageRoute
        , shortName : Maybe String
        , sourceIcon : Image
        }
    }
    -> Pages.Program userModel userMsg metadata view
application config =
    Pages.application
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , document = Dict.fromList config.documents
        , content = RawContent.content
        , toJsPort = toJsPort
        , head = config.head
        , manifest =
            { backgroundColor = config.manifest.backgroundColor
            , categories = config.manifest.categories
            , displayMode = config.manifest.displayMode
            , orientation = config.manifest.orientation
            , description = config.manifest.description
            , iarcRatingId = config.manifest.iarcRatingId
            , name = config.manifest.name
            , themeColor = config.manifest.themeColor
            , startUrl = Just (routeToString config.manifest.startUrl)
            , shortName = config.manifest.shortName
            , sourceIcon = "./" ++ imageUrl config.manifest.sourceIcon
            }
        }
${staticRouteStuff(staticRoutes)}
`;
}

function elmPagesCliFile(staticRoutes) {
  return `port module PagesNew exposing ${exposingList}

import Dict exposing (Dict)
import Color exposing (Color)
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages
import Pages.ContentCache exposing (Page)
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import RawContent
import Url.Parser as Url exposing ((</>), s)
import Pages.Document


port toJsPort : Json.Encode.Value -> Cmd msg


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , documents : List (Pages.Document.DocumentParser metadata view)
    , head : metadata -> List Head.Tag
    , manifest :
        { backgroundColor : Maybe Color
        , categories : List Category
        , displayMode : DisplayMode
        , orientation : Orientation
        , description : String
        , iarcRatingId : Maybe String
        , name : String
        , themeColor : Maybe Color
        , startUrl : PageRoute
        , shortName : Maybe String
        , sourceIcon : Image
        }
    }
    -> Pages.Program userModel userMsg metadata view
application config =
    Pages.cliApplication
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , document = Dict.fromList config.documents
        , content = RawContent.content
        , toJsPort = toJsPort
        , head = config.head
        , manifest =
            { backgroundColor = config.manifest.backgroundColor
            , categories = config.manifest.categories
            , displayMode = config.manifest.displayMode
            , orientation = config.manifest.orientation
            , description = config.manifest.description
            , iarcRatingId = config.manifest.iarcRatingId
            , name = config.manifest.name
            , themeColor = config.manifest.themeColor
            , startUrl = Just (routeToString config.manifest.startUrl)
            , shortName = config.manifest.shortName
            , sourceIcon = "./" ++ imageUrl config.manifest.sourceIcon
            }
        }


${staticRouteStuff(staticRoutes)}
`;
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
