module Pages.Internal exposing
    ( Internal
    , ApplicationType(..)
    )

{-| TODO

@docs Internal

@docs ApplicationType

-}

import Json.Encode
import Pages.Internal.Platform


{-| TODO
-}
type ApplicationType
    = Browser
    | Cli


{-| TODO
-}
type alias Internal pathKey =
    { applicationType : ApplicationType
    , content : Pages.Internal.Platform.Content
    , pathKey : pathKey
    , toJsPort : Json.Encode.Value -> Cmd Never
    }
