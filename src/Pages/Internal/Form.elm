module Pages.Internal.Form exposing (Response(..), Validation(..), ViewField, unwrapResponse)

import Dict exposing (Dict)
import Form.FieldStatus exposing (FieldStatus)
import Json.Encode as Encode


type Validation error parsed kind field
    = Validation (Maybe (ViewField kind)) (Maybe String) ( Maybe parsed, Dict String (List error) )


{-| -}
type alias ViewField kind =
    { value : Maybe String
    , status : FieldStatus
    , kind : ( kind, List ( String, Encode.Value ) )
    }


{-| -}
type Response error
    = Response
        { fields : List ( String, String )
        , errors : Dict String (List error)
        }


unwrapResponse : Response error -> { fields : List ( String, String ), errors : Dict String (List error) }
unwrapResponse (Response response) =
    response
