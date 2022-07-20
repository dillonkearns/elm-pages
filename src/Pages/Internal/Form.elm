module Pages.Internal.Form exposing (Named(..), Validation(..), ViewField)

import Dict exposing (Dict)
import Json.Encode as Encode
import Pages.FormState


type Validation error parsed kind
    = Validation (Maybe (ViewField kind)) (Maybe String) ( Maybe parsed, Dict String (List error) )


{-| -}
type alias ViewField kind =
    { value : Maybe String
    , status : Pages.FormState.FieldStatus
    , kind : ( kind, List ( String, Encode.Value ) )
    }


type Named
    = Named
