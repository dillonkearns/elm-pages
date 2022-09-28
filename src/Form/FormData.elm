module Form.FormData exposing (FormData, Method(..))

{-|

@docs FormData, Method

-}


{-| -}
type alias FormData =
    { fields : List ( String, String )
    , method : Method
    , action : String
    , id : Maybe String
    }


{-| -}
type Method
    = Get
    | Post
