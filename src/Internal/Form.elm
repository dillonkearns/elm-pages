module Internal.Form exposing (FieldDefinition(..), Form(..), Method(..), RenderOptions, methodToString)

{-| -}

import Dict exposing (Dict)
import Pages.FormState exposing (FormState)


type Form error combineAndView parsed input userMsg
    = Form
        (RenderOptions error parsed userMsg)
        (List ( String, FieldDefinition ))
        (Maybe input
         -> FormState
         ->
            { result : Dict String (List error)
            , isMatchCandidate : Bool
            , combineAndView : combineAndView
            }
        )
        (input -> List ( String, Maybe String ))


type alias RenderOptions error parsed userMsg =
    { method : Method
    , onSubmit : Maybe ({ fields : List ( String, String ), parsed : ( Maybe parsed, Dict String (List error) ) } -> userMsg)
    }


{-| -}
type Method
    = Post
    | Get


{-| -}
type FieldDefinition
    = RegularField
    | HiddenField


methodToString : Method -> String
methodToString method =
    case method of
        Post ->
            "POST"

        Get ->
            "GET"
