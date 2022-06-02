module Pages.Msg exposing
    ( Msg(..)
    , map, onSubmit, fetcherOnSubmit
    )

{-|

@docs Msg

@docs map, onSubmit, fetcherOnSubmit

-}

import FormDecoder
import Html exposing (Attribute)
import Html.Attributes
import Json.Decode


{-| -}
type Msg userMsg
    = UserMsg userMsg
    | Submit FormDecoder.FormData
    | SubmitFetcher FormDecoder.FormData
    | FormFieldEvent Json.Decode.Value


{-| -}
onSubmit : Attribute (Msg userMsg)
onSubmit =
    FormDecoder.formDataOnSubmit
        |> Html.Attributes.map Submit


{-| -}
fetcherOnSubmit : Attribute (Msg userMsg)
fetcherOnSubmit =
    FormDecoder.formDataOnSubmit
        |> Html.Attributes.map SubmitFetcher


{-| -}
map : (a -> b) -> Msg a -> Msg b
map mapFn msg =
    case msg of
        UserMsg userMsg ->
            UserMsg (mapFn userMsg)

        Submit info ->
            Submit info

        SubmitFetcher info ->
            SubmitFetcher info

        FormFieldEvent value ->
            FormFieldEvent value
