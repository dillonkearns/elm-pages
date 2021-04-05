module Metadata exposing (ArticleMetadata, DocMetadata, Metadata(..), PageMetadata)

import Data.Author
import Date exposing (Date)
import Pages
import Pages.ImagePath exposing (ImagePath)


type Metadata
    = Page PageMetadata
    | Article ArticleMetadata
    | Doc DocMetadata
    | BlogIndex
    | Showcase


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , author : Data.Author.Author
    , image : ImagePath Pages.PathKey
    , draft : Bool
    }


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }
