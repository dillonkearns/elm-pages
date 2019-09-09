module Metadata exposing (ArticleMetadata, DocMetadata, Metadata(..), PageMetadata)

import Date exposing (Date)
import Dict exposing (Dict)
import Element exposing (Element)
import Element.Font as Font


type Metadata
    = Page PageMetadata
    | Article ArticleMetadata
    | Doc DocMetadata


type alias ArticleMetadata =
    { author : String
    , title : String
    , description : String
    , published : Date
    }


type alias DocMetadata =
    { title : String
    }


type alias PageMetadata =
    { title : String }
