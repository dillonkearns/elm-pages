generateRawContent = require("./generate-raw-content.js");
const exposingList =
  "(PathKey, allPages, allImages, internals, images, isValidRoute, pages)";

function staticRouteStuff(staticRoutes) {
  return `


${staticRoutes.allRoutes}

${staticRoutes.routeRecord}

${staticRoutes.imageAssetsRecord}

allImages : List (ImagePath PathKey)
allImages =
    [${staticRoutes.allImages.join("\n    , ")}
    ]


isValidRoute : String -> Result String ()
isValidRoute route =
    let
        validRoutes =
            List.map PagePath.toString allPages
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
  return `port module Pages exposing ${exposingList}

import Color exposing (Color)
import Pages.Internal
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages.Platform
import Pages.ContentCache exposing (Page)
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import Url.Parser as Url exposing ((</>), s)
import Pages.Document as Document
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Directory as Directory exposing (Directory)



type PathKey
    = PathKey


buildImage : List String -> ImagePath PathKey
buildImage path =
    ImagePath.build PathKey ("images" :: path)



buildPage : List String -> PagePath PathKey
buildPage path =
    PagePath.build PathKey path


directoryWithIndex : List String -> Directory PathKey Directory.WithIndex
directoryWithIndex path =
    Directory.withIndex PathKey allPages path


directoryWithoutIndex : List String -> Directory PathKey Directory.WithoutIndex
directoryWithoutIndex path =
    Directory.withoutIndex PathKey allPages path


port toJsPort : Json.Encode.Value -> Cmd msg


internals : Pages.Internal.Internal PathKey
internals =
    { applicationType = Pages.Internal.Browser
    , toJsPort = toJsPort
    , content = content
    , pathKey = PathKey
    }
        
${staticRouteStuff(staticRoutes)}

${generateRawContent(markdownContent, markupContent, false)}
`;
}

function elmPagesCliFile(staticRoutes, markdownContent, markupContent) {
  return `port module Pages exposing ${exposingList}

import Color exposing (Color)
import Pages.Internal
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages.Platform
import Pages.ContentCache exposing (Page)
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import Url.Parser as Url exposing ((</>), s)
import Pages.Document as Document
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Directory as Directory exposing (Directory)


type PathKey
    = PathKey


buildImage : List String -> ImagePath PathKey
buildImage path =
    ImagePath.build PathKey ("images" :: path)


buildPage : List String -> PagePath PathKey
buildPage path =
    PagePath.build PathKey path


directoryWithIndex : List String -> Directory PathKey Directory.WithIndex
directoryWithIndex path =
    Directory.withIndex PathKey allPages path


directoryWithoutIndex : List String -> Directory PathKey Directory.WithoutIndex
directoryWithoutIndex path =
    Directory.withoutIndex PathKey allPages path


port toJsPort : Json.Encode.Value -> Cmd msg


internals : Pages.Internal.Internal PathKey
internals =
    { applicationType = Pages.Internal.Cli
    , toJsPort = toJsPort
    , content = content
    , pathKey = PathKey
    }


${staticRouteStuff(staticRoutes)}

${generateRawContent(markdownContent, markupContent, true)}
`;
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
