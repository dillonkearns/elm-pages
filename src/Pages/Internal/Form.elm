module Pages.Internal.Form exposing (AnyValidation(..), ViewField)

import Dict exposing (Dict)
import Json.Encode as Encode
import Pages.FormState


type AnyValidation error parsed kind field
    = Validation (Maybe (ViewField kind)) (Maybe String) ( Maybe parsed, Dict String (List error) )


{-| -}
type alias ViewField kind =
    { value : Maybe String
    , status : Pages.FormState.FieldStatus
    , kind : ( kind, List ( String, Encode.Value ) )
    }
