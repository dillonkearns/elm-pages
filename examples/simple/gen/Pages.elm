port module Pages exposing (PathKey, allPages, allImages, internals, images, isValidRoute, pages, builtAt)

import Color exposing (Color)
import Pages.Internal
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Pages.Platform
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import Url.Parser as Url exposing ((</>), s)
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Directory as Directory exposing (Directory)
import Time


builtAt : Time.Posix
builtAt =
    Time.millisToPosix 1602471727765


type PathKey
    = PathKey


buildImage : List String -> ImagePath.Dimensions -> ImagePath PathKey
buildImage path dimensions =
    ImagePath.build PathKey ("images" :: path) dimensions


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

port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


internals : Pages.Internal.Internal PathKey
internals =
    { applicationType = Pages.Internal.Browser
    , toJsPort = toJsPort
    , fromJsPort = fromJsPort identity
    , content = content
    , pathKey = PathKey
    }




allPages : List (PagePath PathKey)
allPages =
    [ (buildPage [ "elm-markdown" ])
    , (buildPage [  ])
    ]

pages =
    { elmMarkdown = (buildPage [ "elm-markdown" ])
    , index = (buildPage [  ])
    , directory = directoryWithIndex []
    }

images =
    { iconPng = (buildImage [ "icon-png.png" ] { width = 50, height = 75 })
    , directory = directoryWithoutIndex []
    }


allImages : List (ImagePath PathKey)
allImages =
    [(buildImage [ "icon-png.png" ] { width = 50, height = 75 })
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
        ("Valid routes:\n"
            ++ String.join "\n\n" validRoutes
        )
            |> Err


content : List ( List String, { extension: String, frontMatter : String, body : Maybe String } )
content =
    [ 
  ( ["elm-markdown"]
    , { frontMatter = "{\"title\":\"Hello from another page.\",\"type\":\"page\",\"repo\":\"elm-markdown\"}"
    , body = Nothing
    , extension = "md"
    } )
  ,
  ( []
    , { frontMatter = "{\"title\":\"elm-pages - a statically typed site generator\",\"type\":\"page\",\"repo\":\"elm-pages\"}"
    , body = Nothing
    , extension = "md"
    } )
  
    ]
