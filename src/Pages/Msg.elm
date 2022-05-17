module Pages.Msg exposing
    ( Msg(..)
    , map, onSubmit
    )

{-|

@docs Msg

@docs map, onSubmit

-}

import FormDecoder
import Html exposing (Attribute)
import Html.Attributes


{-| -}
type Msg userMsg
    = UserMsg userMsg
    | Submit FormDecoder.FormData


{-| -}
onSubmit : Attribute (Msg userMsg)
onSubmit =
    FormDecoder.formDataOnSubmit
        |> Html.Attributes.map Submit


{-| -}
map : (a -> b) -> Msg a -> Msg b
map mapFn msg =
    case msg of
        UserMsg userMsg ->
            UserMsg (mapFn userMsg)

        Submit info ->
            Submit info
