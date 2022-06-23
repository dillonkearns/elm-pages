module Form.Value exposing
    ( Value, date, float, int, string, toString
    , compare
    )

{-|

@docs Value, date, float, int, string, toString

-}

import Date exposing (Date)


type Kind
    = StringValue
    | DateValue
    | IntValue
    | FloatValue


{-| -}
type Value dataType
    = Value Kind String


{-| -}
toString : Value dataType -> String
toString (Value kind rawValue) =
    rawValue


{-| -}
date : Date -> Value Date
date date_ =
    date_
        |> Date.toIsoString
        |> Value DateValue


{-| -}
float : Float -> Value Float
float float_ =
    float_
        |> String.fromFloat
        |> Value FloatValue


{-| -}
int : Int -> Value Int
int int_ =
    int_
        |> String.fromInt
        |> Value IntValue


{-| -}
string : String -> Value String
string string_ =
    string_
        |> Value StringValue


compare : String -> Value value -> Order
compare a (Value kind rawValue) =
    case kind of
        IntValue ->
            case ( String.toInt a, String.toInt rawValue ) of
                ( Just parsedA, Just parsedB ) ->
                    Basics.compare parsedA parsedB

                _ ->
                    LT

        StringValue ->
            -- TODO
            LT

        DateValue ->
            Result.map2 Date.compare
                (Date.fromIsoString a)
                (Date.fromIsoString rawValue)
                |> Result.withDefault LT

        FloatValue ->
            -- TODO
            LT
