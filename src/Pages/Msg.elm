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
    | SubmitFetcher FormDecoder.FormData
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

        SubmitIfValid info isValid ->
            SubmitIfValid info isValid

        SubmitFetcher info ->
            SubmitFetcher info

        FormFieldEvent value ->
            FormFieldEvent value
