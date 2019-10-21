module Pages.Internal exposing (..)

import Json.Encode
import Pages.Internal.Platform


type ApplicationType
    = Browser
    | Cli


type alias Internal pathKey =
    { applicationType : ApplicationType
    , content : Pages.Internal.Platform.Content
    , pathKey : pathKey
    , toJsPort : Json.Encode.Value -> Cmd Never
    }
