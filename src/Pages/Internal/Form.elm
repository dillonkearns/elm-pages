module Pages.Internal.Form exposing (Named(..), Validation(..))

import Dict exposing (Dict)


type Validation error parsed named
    = Validation (Maybe String) ( Maybe parsed, Dict String (List error) )


type Named
    = Named
