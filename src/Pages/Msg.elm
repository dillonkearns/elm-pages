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
import Html.Attributes as Attr
import Json.Decode


{-| -}
type Msg userMsg
    = UserMsg userMsg
    | Submit FormDecoder.FormData
    | SubmitIfValid String FormDecoder.FormData Bool
    | SubmitFetcher String FormDecoder.FormData Bool
    | FormFieldEvent Json.Decode.Value


{-| -}
onSubmit : Attribute (Msg userMsg)
onSubmit =
    FormDecoder.formDataOnSubmit
        |> Attr.map Submit


{-| -}
submitIfValid : String -> (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
submitIfValid formId isValid =
    FormDecoder.formDataOnSubmit
        |> Attr.map (\formData -> SubmitIfValid formId formData (isValid formData.fields))


{-| -}
fetcherOnSubmit : String -> (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
fetcherOnSubmit formId isValid =
    FormDecoder.formDataOnSubmit
        |> Attr.map (\formData -> SubmitFetcher formId formData (isValid formData.fields))


{-| -}
map : (a -> b) -> Msg a -> Msg b
map mapFn msg =
    case msg of
        UserMsg userMsg ->
            UserMsg (mapFn userMsg)

        Submit info ->
            Submit info

        SubmitIfValid formId info isValid ->
            SubmitIfValid formId info isValid

        SubmitFetcher formId info isValid ->
            SubmitFetcher formId info isValid

        FormFieldEvent value ->
            FormFieldEvent value
