module Site exposing (..)

import Color
import Pages exposing (images, pages)
import Pages.Manifest as Manifest
import Pages.Manifest.Category


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"


manifest : Manifest.Config Pages.PathKey
manifest =
    { backgroundColor = Just Color.white
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Just Color.white
    , startUrl = pages.index
    , shortName = Just "elm-pages"
    , sourceIcon = images.iconPng
    }


tagline : String
tagline =
    "A statically typed site generator - elm-pages"
