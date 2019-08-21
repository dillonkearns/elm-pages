const exposingList =
  "(application, PageRoute, all, pages, routeToString, Image, imageUrl, images)";

function staticRouteStuff(staticRoutes) {
  return `

type PageRoute = PageRoute (List String)

type Image = Image (List String)

imageUrl : Image -> String
imageUrl (Image path) =
    "/"
        ++ String.join "/" path

${staticRoutes.allRoutes}

${staticRoutes.routeRecord}

${staticRoutes.urlParser}

${staticRoutes.imageAssetsRecord}

routeToString : PageRoute -> String
routeToString (PageRoute route) =
    "/"
      ++ (route |> String.join "/")
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


port toJsPort : Json.Encode.Value -> Cmd msg


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , parser : Pages.Parser metadata view
    , head : metadata -> List Head.Tag
    , frontmatterParser : Json.Decode.Decoder metadata
    , markdownToHtml : String -> view
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
        , parser = config.parser
        , frontmatterParser = config.frontmatterParser
        , content = RawContent.content
        , markdownToHtml = config.markdownToHtml
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


port toJsPort : Json.Encode.Value -> Cmd msg


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , parser : Pages.Parser metadata view
    , head : metadata -> List Head.Tag
    , frontmatterParser : Json.Decode.Decoder metadata
    , markdownToHtml : String -> view
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
        , parser = config.parser
        , frontmatterParser = config.frontmatterParser
        , content = RawContent.content
        , markdownToHtml = config.markdownToHtml
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
