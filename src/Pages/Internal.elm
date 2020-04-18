module Pages.Internal exposing
    ( Internal
    , ApplicationType(..)
    )

{-| You don't need to use this unless you want to play around with the internals of `elm-pages` to build
a similar framework and hook into the low-level details. Otherwise, just grab the `Pages.Internal.Internal` value
that is in the generated `Pages` module (see <Pages.Platform>).

@docs Internal

@docs ApplicationType

-}

import Json.Decode
import Json.Encode
import Pages.Internal.Platform


{-| Internal detail to track whether to run the CLI step or the runtime step in the browser.
-}
type ApplicationType
    = Browser
    | Cli


{-| This type is generated for you in your `gen/Pages.elm` module (see <Pages.Platform>).
-}
type alias Internal pathKey =
    { applicationType : ApplicationType
    , content : Pages.Internal.Platform.Content
    , pathKey : pathKey
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Json.Decode.Value
    }
