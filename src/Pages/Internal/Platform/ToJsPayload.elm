module Pages.Internal.Platform.ToJsPayload exposing (..)

import Dict exposing (Dict)
import Pages.Manifest as Manifest


type ToJsPayload pathKey
    = Errors String
    | Success (ToJsSuccessPayload pathKey)


type alias ToJsSuccessPayload pathKey =
    { pages : Dict String (Dict String String)
    , manifest : Manifest.Config pathKey
    , filesToGenerate : List FileToGenerate
    , staticHttpCache : Dict String String
    , errors : List String
    }


type alias FileToGenerate =
    { path : List String
    , content : String
    }
