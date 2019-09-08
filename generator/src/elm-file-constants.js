generateRawContent = require("./generate-raw-content.js");
const exposingList =
  "(PathKey, allPages, allImages, application, images, isValidRoute, pages)";

function staticRouteStuff(staticRoutes) {
  return `


${staticRoutes.allRoutes}

${staticRoutes.routeRecord}

${staticRoutes.imageAssetsRecord}

allImages : List (Path PathKey Path.ToImage)
allImages =
    [${staticRoutes.allImages.join("\n    , ")}
    ]


isValidRoute : String -> Result String ()
isValidRoute route =
    let
        validRoutes =
            List.map Path.toString allPages
    in
    if
        (route |> String.startsWith "http://")
            || (route |> String.startsWith "https://")
            || (route |> String.startsWith "#")
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

function elmPagesUiFile(staticRoutes, markdownContent, markupContent) {
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
import Url.Parser as Url exposing ((</>), s)
import Pages.Document
import Pages.Path as Path exposing (Path)


type PathKey
    = PathKey


buildImage : List String -> Path PathKey Path.ToImage
buildImage path =
    Path.buildImage PathKey ("images" :: path)



buildPage : List String -> Path PathKey Path.ToPage
buildPage path =
    Path.buildPage PathKey path
port toJsPort : Json.Encode.Value -> Cmd msg


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , head : metadata -> List (Head.Tag PathKey)
    , documents : List (Pages.Document.DocumentParser metadata view)
    , manifest : Pages.Manifest.Config PathKey
    , siteUrl : String
    }
    -> Pages.Program userModel userMsg metadata view
application config =
    Pages.application
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , document = Dict.fromList config.documents
        , content = content
        , toJsPort = toJsPort
        , head = config.head
        , manifest = config.manifest
        , siteUrl = config.siteUrl
        }
${staticRouteStuff(staticRoutes)}

${generateRawContent(markdownContent, markupContent)}
`;
}

function elmPagesCliFile(staticRoutes, markdownContent, markupContent) {
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
import Url.Parser as Url exposing ((</>), s)
import Pages.Document
import Pages.Path as Path exposing (Path)

type PathKey
    = PathKey


buildImage : List String -> Path PathKey Path.ToImage
buildImage path =
    Path.buildImage PathKey ("images" :: path)


buildPage : List String -> Path PathKey Path.ToPage
buildPage path =
    Path.buildPage PathKey path

port toJsPort : Json.Encode.Value -> Cmd msg


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , documents : List (Pages.Document.DocumentParser metadata view)
    , head : metadata -> List (Head.Tag PathKey)
    , manifest : Pages.Manifest.Config PathKey
    , siteUrl : String
    }
    -> Pages.Program userModel userMsg metadata view
application config =
    Pages.cliApplication
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , document = Dict.fromList config.documents
        , content = content
        , toJsPort = toJsPort
        , head = config.head
        , manifest = config.manifest
        , siteUrl = config.siteUrl
        }


${staticRouteStuff(staticRoutes)}

${generateRawContent(markdownContent, markupContent)}
`;
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
