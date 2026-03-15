module Pages.Internal.Script exposing
    ( IntrospectionContext
    , Script(..)
    , metadata
    )

import BackendTask exposing (BackendTask)
import Cli.Program as Program
import FatalError exposing (FatalError)
import Html exposing (Html)
import Json.Encode as Encode


{-| -}
type alias IntrospectionContext =
    { moduleName : String
    , path : String
    }


{-| -}
type Script
    = Script
        { toConfig :
            (Maybe { indent : Int, newLines : Bool }
             -> Html Never
             -> String
            )
            -> Program.Config (BackendTask FatalError ())
        , metadata : Maybe (IntrospectionContext -> Encode.Value)
        }


{-| -}
metadata : IntrospectionContext -> Script -> Maybe Encode.Value
metadata context (Script script) =
    script.metadata
        |> Maybe.map (\toMetadata -> toMetadata context)
