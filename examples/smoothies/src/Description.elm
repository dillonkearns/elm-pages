module Description exposing (Description(..), Error(..), empty, errorToString, fromString, maxLength, toString)


type Description
    = Description String


type Error
    = DescriptionTooLong Int


errorToString : Error -> String
errorToString error =
    case error of
        DescriptionTooLong length ->
            "Description is "
                ++ String.fromInt length
                ++ " characters long. Keep it under "
                ++ String.fromInt maxLength
                ++ "."


maxLength : number
maxLength =
    3000


fromString : String -> Result Error Description
fromString text =
    let
        trimmed =
            String.trim text
    in
    if String.length trimmed > maxLength then
        Err (DescriptionTooLong (String.length trimmed))

    else
        Ok (Description trimmed)


toString : Description -> String
toString (Description description) =
    description


empty : Description
empty =
    Description ""
