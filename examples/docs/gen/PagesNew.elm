port module PagesNew exposing (PathKey, allPages, allImages, application, images, isValidRoute, pages)

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
        }



allPages : List (Path PathKey Path.ToPage)
allPages =
    [ (buildPage [ "authors", "dillon-kearns" ])
    , (buildPage [ "blog", "types-over-conventions" ])
    , (buildPage [ "docs", "directory-structure" ])
    , (buildPage [ "docs" ])
    , (buildPage [  ])
    ]

pages =
    { authors =
        { dillonKearns = (buildPage [ "authors", "dillon-kearns" ])
        , all = [ (buildPage [ "authors", "dillon-kearns" ]) ]
        }
    , blog =
        { typesOverConventions = (buildPage [ "blog", "types-over-conventions" ])
        , all = [ (buildPage [ "blog", "types-over-conventions" ]) ]
        }
    , docs =
        { directoryStructure = (buildPage [ "docs", "directory-structure" ])
        , index = (buildPage [ "docs" ])
        , all = [ (buildPage [ "docs", "directory-structure" ]), (buildPage [ "docs" ]) ]
        }
    , index = (buildPage [  ])
    , all = [ (buildPage [  ]) ]
    }

images =
    { dillon = (buildImage [ "dillon.jpg" ])
    , icon = (buildImage [ "icon.svg" ])
    , mountains = (buildImage [ "mountains.jpg" ])
    , all = [ (buildImage [ "dillon.jpg" ]), (buildImage [ "icon.svg" ]), (buildImage [ "mountains.jpg" ]) ]
    }

allImages : List (Path PathKey Path.ToImage)
allImages =
    [(buildImage [ "dillon.jpg" ])
    , (buildImage [ "icon.svg" ])
    , (buildImage [ "mountains.jpg" ])
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
        ("Valid routes:\n"
            ++ String.join "\n\n" validRoutes
        )
            |> Err


content : List ( List String, { extension: String, frontMatter : String, body : Maybe String } )
content =
    [ 
  ( ["authors", "dillon-kearns"]
    , { frontMatter = """{"name":"Dillon Kearns","avatar":"/images/dillon.jpg","bio":"Elm developer and educator. Founder of Incremental Elm Consulting.","type":"author"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["blog", "types-over-conventions"]
    , { frontMatter = """{"type":"blog","author":"Dillon Kearns","title":"Types Over Conventions","description":"TODO","published":"2019-09-09"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["docs", "directory-structure"]
    , { frontMatter = """{"title":"Directory Structure","type":"doc"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["docs"]
    , { frontMatter = """{"title":"Quick Start","type":"doc"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( []
    , { frontMatter = """{"title":"elm-pages - a statically typed site generator","type":"page"}
""" , body = Nothing
    , extension = "md"
    } )
  
    ]
