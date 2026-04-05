module EmailAddress exposing (EmailAddress, fromString, toString)


type EmailAddress
    = EmailAddress String


fromString : String -> Maybe EmailAddress
fromString str =
    if String.contains "@" str then
        Just (EmailAddress str)

    else
        Nothing


toString : EmailAddress -> String
toString (EmailAddress str) =
    str
