module Pages.FormData exposing (FormData)

{-|

@docs FormData

-}

import Form


{-| -}
type alias FormData =
    { fields : List ( String, String )
    , method : Form.Method
    , action : String
    , id : Maybe String
    }
