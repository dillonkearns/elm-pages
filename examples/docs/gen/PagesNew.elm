port module PagesNew exposing (application, PageRoute, all, pages, routeToString, Image, imageUrl, images, allImages, isValidRoute)

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
        , content = content
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


type PageRoute = PageRoute (List String)

type Image = Image (List String)

imageUrl : Image -> String
imageUrl (Image path) =
    "/"
        ++ String.join "/" ("images" :: path)

all : List PageRoute
all =
    [ (PageRoute [ "blog", "types-over-conventions" ])
    , (PageRoute [ "docs", "directory-structure" ])
    , (PageRoute [ "docs" ])
    , (PageRoute [  ])
    , (PageRoute [ "markdown" ])
    ]

pages =
    { blog =
        { typesOverConventions = (PageRoute [ "blog", "types-over-conventions" ])
        , all = [ (PageRoute [ "blog", "types-over-conventions" ]) ]
        }
    , docs =
        { directoryStructure = (PageRoute [ "docs", "directory-structure" ])
        , index = (PageRoute [ "docs" ])
        , all = [ (PageRoute [ "docs", "directory-structure" ]), (PageRoute [ "docs" ]) ]
        }
    , index = (PageRoute [  ])
    , markdown = (PageRoute [ "markdown" ])
    , all = [ (PageRoute [  ]), (PageRoute [ "markdown" ]) ]
    }

urlParser : Url.Parser (PageRoute -> a) a
urlParser =
    Url.oneOf
        [ Url.map (PageRoute [ "blog", "types-over-conventions" ]) (s "blog" </> s "types-over-conventions")
        , Url.map (PageRoute [ "docs", "directory-structure" ]) (s "docs" </> s "directory-structure")
        , Url.map (PageRoute [ "docs" ]) (s "docs" </> s "index")
        , Url.map (PageRoute [  ]) (s "index")
        , Url.map (PageRoute [ "markdown" ]) (s "markdown")
        ] 

images =
    { icon = (Image [ "icon.svg" ])
    , mountains = (Image [ "mountains.jpg" ])
    , all = [ (Image [ "icon.svg" ]), (Image [ "mountains.jpg" ]) ]
    }

allImages : List Image
allImages =
    [(Image [ "icon.svg" ])
    , (Image [ "mountains.jpg" ])
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
        ("Valid routes:\n"
            ++ String.join "\n\n" validRoutes
        )
            |> Err


content : List ( List String, { extension: String, frontMatter : String, body : Maybe String } )
content =
    [ 
  ( ["blog", "types-over-conventions"]
    , { frontMatter = """{"author":"Dillon Kearns","title":"Types Over Conventions","description":"TODO"}
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
    , { frontMatter = """{"title":"elm-pages - a statically typed site generator"}
""" , body = Nothing
    , extension = "md"
    } )
  ,
  ( ["markdown"]
    , { frontMatter = """{"title":"Hello from markdown! 👋"}
""" , body = Nothing
    , extension = "md"
    } )
  
    ]
