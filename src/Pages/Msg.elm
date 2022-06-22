module Pages.Msg exposing
    ( Msg(..)
    , map, onSubmit, fetcherOnSubmit, submitIfValid
    )

{-|

@docs Msg

@docs map, onSubmit, fetcherOnSubmit, submitIfValid

-}

import FormDecoder
import Html exposing (Attribute)
import Html.Attributes
import Json.Decode


{-| -}
type Msg userMsg
    = UserMsg userMsg
    | Submit FormDecoder.FormData
    | SubmitIfValid FormDecoder.FormData Bool
    | SubmitFetcher FormDecoder.FormData Bool
    | FormFieldEvent Json.Decode.Value


{-| -}
onSubmit : Attribute (Msg userMsg)
onSubmit =
    FormDecoder.formDataOnSubmit
        |> Html.Attributes.map Submit


{-| -}
submitIfValid : (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
submitIfValid isValid =
    FormDecoder.formDataOnSubmit
        |> Html.Attributes.map (\formData -> SubmitIfValid formData (isValid formData.fields))


{-| -}
fetcherOnSubmit : (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
fetcherOnSubmit isValid =
    FormDecoder.formDataOnSubmit
        |> Html.Attributes.map (\formData -> SubmitFetcher formData (isValid formData.fields))


{-| -}
map : (a -> b) -> Msg a -> Msg b
map mapFn msg =
    case msg of
        UserMsg userMsg ->
            UserMsg (mapFn userMsg)

        Submit info ->
            Submit info

        SubmitIfValid info isValid ->
            SubmitIfValid info isValid

        SubmitFetcher info isValid ->
            SubmitFetcher info isValid

        FormFieldEvent value ->
            FormFieldEvent value
