module Internal.Field exposing (Field(..), FieldInfo)

{-| -}

import Json.Encode as Encode


type Field error parsed input initial kind constraints
    = Field (FieldInfo error parsed input initial) kind


{-| -}
type alias FieldInfo error parsed input initial =
    { initialValue : input -> Maybe String
    , decode : Maybe String -> ( Maybe parsed, List error )
    , properties : List ( String, Encode.Value )
    , initialToString : initial -> String
    , compare : String -> initial -> Order
    }
