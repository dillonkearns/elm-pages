module Form.Value exposing (Value, date, float, int, string, toString)

{-|

@docs Value, date, float, int, string, toString

-}

import Date exposing (Date)


{-| -}
type Value dataType
    = Value String


{-| -}
toString : Value dataType -> String
toString (Value rawValue) =
    rawValue


{-| -}
date : Date -> Value Date
date date_ =
    date_
        |> Date.toIsoString
        |> Value


{-| -}
float : Float -> Value Float
float float_ =
    float_
        |> String.fromFloat
        |> Value


{-| -}
int : Int -> Value Int
int int_ =
    int_
        |> String.fromInt
        |> Value


{-| -}
string : String -> Value String
string string_ =
    string_
        |> Value
