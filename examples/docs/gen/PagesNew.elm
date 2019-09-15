port module PagesNew exposing (PathKey, allImages, allPages, application, images, isValidRoute, pages)

import Color exposing (Color)
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages
import Pages.ContentCache exposing (Page)
import Pages.Directory as Directory exposing (Directory)
import Pages.Document
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import Pages.PagePath as PagePath exposing (PagePath)
import Url.Parser as Url exposing ((</>), s)


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


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( PagePath PathKey, metadata ) -> Page metadata view PathKey -> { title : String, body : Html userMsg }
    , head : metadata -> List (Head.Tag PathKey)
    , documents : List ( String, Pages.Document.DocumentHandler metadata view )
    , manifest : Pages.Manifest.Config PathKey
    , canonicalSiteUrl : String
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
        , canonicalSiteUrl = config.canonicalSiteUrl
        , pathKey = PathKey
        }


allPages : List (PagePath PathKey)
allPages =
    [ buildPage [ "blog" ]
    , buildPage [ "blog", "types-over-conventions" ]
    , buildPage [ "docs", "directory-structure" ]
    , buildPage [ "docs" ]
    , buildPage []
    ]


pages =
    { blog =
        { index = buildPage [ "blog" ]
        , typesOverConventions = buildPage [ "blog", "types-over-conventions" ]
        , directory = directoryWithIndex [ "blog" ]
        }
    , docs =
        { directoryStructure = buildPage [ "docs", "directory-structure" ]
        , index = buildPage [ "docs" ]
        , directory = directoryWithIndex [ "docs" ]
        }
    , index = buildPage []
    , directory = directoryWithIndex []
    }


images =
    { dillon = buildImage [ "dillon.jpg" ]
    , icon = buildImage [ "icon.svg" ]
    , mountains = buildImage [ "mountains.jpg" ]
    , directory = directoryWithoutIndex []
    }


allImages : List (ImagePath PathKey)
allImages =
    [ buildImage [ "dillon.jpg" ]
    , buildImage [ "icon.svg" ]
    , buildImage [ "mountains.jpg" ]
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


content : List ( List String, { extension : String, frontMatter : String, body : Maybe String } )
content =
    [ ( [ "blog" ]
      , { frontMatter = """{"title":"elm-pages blog","type":"blog-index"}
"""
        , body = Nothing
        , extension = "md"
        }
      )
    , ( [ "blog", "types-over-conventions" ]
      , { frontMatter = """{"type":"blog","author":"Dillon Kearns","title":"Types Over Conventions","description":"TODO","published":"2019-09-09"}
"""
        , body = Nothing
        , extension = "md"
        }
      )
    , ( [ "docs", "directory-structure" ]
      , { frontMatter = """{"title":"Directory Structure","type":"doc"}
"""
        , body = Nothing
        , extension = "md"
        }
      )
    , ( [ "docs" ]
      , { frontMatter = """{"title":"Quick Start","type":"doc"}
"""
        , body = Nothing
        , extension = "md"
        }
      )
    , ( []
      , { frontMatter = """{"title":"elm-pages - a statically typed site generator","type":"page"}
"""
        , body = Nothing
        , extension = "md"
        }
      )
    ]
