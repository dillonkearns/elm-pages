module Form.FieldStatus exposing (FieldStatus(..), fieldStatusToString)

{-| elm-pages manages the client-side state of fields, including Status which you can use to determine when
in the user's workflow to show validation errors.


## Field Status

@docs FieldStatus, fieldStatusToString

-}


{-| -}
type FieldStatus
    = NotVisited
    | Focused
    | Changed
    | Blurred


{-| -}
fieldStatusToString : FieldStatus -> String
fieldStatusToString fieldStatus =
    case fieldStatus of
        NotVisited ->
            "NotVisited"

        Focused ->
            "Focused"

        Changed ->
            "Changed"

        Blurred ->
            "Blurred"
