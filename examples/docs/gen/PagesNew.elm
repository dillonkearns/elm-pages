port module PagesNew exposing (PathKey, all, allImages, application, buildPage, images, isValidRoute, pages)

import Color exposing (Color)
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages
import Pages.ContentCache exposing (Page)
import Pages.Document
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import Pages.Path as Path exposing (Path)
import Url.Parser as Url exposing ((</>), s)


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
        }


all : List (Path PathKey Path.ToPage)
all =
    [ buildPage [ "blog", "types-over-conventions" ]
    , buildPage [ "docs", "directory-structure" ]
    , buildPage [ "docs" ]
    , buildPage []
    , buildPage [ "markdown" ]
    ]


pages =
    { blog =
        { typesOverConventions = buildPage [ "blog", "types-over-conventions" ]
        , all = [ buildPage [ "blog", "types-over-conventions" ] ]
        }
    , docs =
        { directoryStructure = buildPage [ "docs", "directory-structure" ]
        , index = buildPage [ "docs" ]
        , all = [ buildPage [ "docs", "directory-structure" ], buildPage [ "docs" ] ]
        }
    , index = buildPage []
    , markdown = buildPage [ "markdown" ]
    , all = [ buildPage [], buildPage [ "markdown" ] ]
    }


urlParser : Url.Parser (Path PathKey Path.ToPage -> a) a
urlParser =
    Url.oneOf
        [ Url.map (buildPage [ "blog", "types-over-conventions" ]) (s "blog" </> s "types-over-conventions")
        , Url.map (buildPage [ "docs", "directory-structure" ]) (s "docs" </> s "directory-structure")
        , Url.map (buildPage [ "docs" ]) (s "docs" </> s "index")
        , Url.map (buildPage []) (s "index")
        , Url.map (buildPage [ "markdown" ]) (s "markdown")
        ]


images =
    { icon = buildImage [ "icon.svg" ]
    , mountains = buildImage [ "mountains.jpg" ]
    , all = [ buildImage [ "icon.svg" ], buildImage [ "mountains.jpg" ] ]
    }


allImages : List (Path PathKey Path.ToImage)
allImages =
    [ buildImage [ "icon.svg" ]
    , buildImage [ "mountains.jpg" ]
    ]


isValidRoute : String -> Result String ()
isValidRoute route =
    let
        validRoutes =
            List.map Path.toString all
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
    [ ( [ "blog", "types-over-conventions" ]
      , { frontMatter = """{"author":"Dillon Kearns","title":"Types Over Conventions","description":"TODO"}
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
      , { frontMatter = """{"title":"elm-pages - a statically typed site generator"}
"""
        , body = Nothing
        , extension = "md"
        }
      )
    , ( [ "markdown" ]
      , { frontMatter = """{"title":"Hello from markdown! 👋"}
"""
        , body = Nothing
        , extension = "md"
        }
      )
    ]
