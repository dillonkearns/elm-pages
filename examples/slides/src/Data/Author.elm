module Data.Author exposing (Author)

import Pages.ImagePath exposing (ImagePath)


type alias Author =
    { name : String
    , avatar : ImagePath
    , bio : String
    }
