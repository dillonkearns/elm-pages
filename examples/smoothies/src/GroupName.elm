module GroupName exposing (Error(..), GroupName(..), fromString, maxLength, minLength, namesMatch, toNonemptyString, toString)

import String.Nonempty exposing (NonemptyString)


type GroupName
    = GroupName NonemptyString


type Error
    = GroupNameTooShort
    | GroupNameTooLong


minLength : number
minLength =
    4


maxLength : number
maxLength =
    50


fromString : String -> Result Error GroupName
fromString text =
    let
        trimmed =
            String.trim text
    in
    if String.length trimmed < minLength then
        Err GroupNameTooShort

    else if String.length trimmed > maxLength then
        Err GroupNameTooLong

    else
        case String.Nonempty.fromString trimmed of
            Just nonempty ->
                Ok (GroupName nonempty)

            Nothing ->
                Err GroupNameTooShort


toString : GroupName -> String
toString (GroupName groupName) =
    String.Nonempty.toString groupName


toNonemptyString : GroupName -> NonemptyString
toNonemptyString (GroupName groupName) =
    groupName


namesMatch : GroupName -> GroupName -> Bool
namesMatch (GroupName name0) (GroupName name1) =
    String.Nonempty.toLower name0 == String.Nonempty.toLower name1
