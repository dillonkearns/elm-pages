module Pages.Internal.Msg exposing
    ( Msg(..)
    , fetcherOnSubmit
    , map
    , onSubmit
    , submitIfValid
    )

import Form.FormData exposing (FormData)
import FormDecoder
import Html exposing (Attribute)
import Html.Attributes as Attr
import Json.Decode


{-| -}
type Msg userMsg
    = UserMsg userMsg
    | Submit FormData
    | SubmitIfValid String FormData Bool (Maybe userMsg)
    | SubmitFetcher String FormData Bool (Maybe userMsg)
    | FormFieldEvent Json.Decode.Value
    | NoOp


{-| -}
onSubmit : Attribute (Msg userMsg)
onSubmit =
    FormDecoder.formDataOnSubmit
        |> Attr.map Submit


{-| -}
submitIfValid : Maybe ({ fields : List ( String, String ) } -> userMsg) -> String -> (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
submitIfValid userMsg formId isValid =
    FormDecoder.formDataOnSubmit
        |> Attr.map
            (\formData ->
                SubmitIfValid formId
                    formData
                    (isValid formData.fields)
                    (userMsg
                        |> Maybe.map
                            (\toUserMsg ->
                                toUserMsg { fields = formData.fields }
                            )
                    )
            )


{-| -}
fetcherOnSubmit : Maybe ({ fields : List ( String, String ) } -> userMsg) -> String -> (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
fetcherOnSubmit userMsg formId isValid =
    FormDecoder.formDataOnSubmit
        |> Attr.map
            (\formData ->
                SubmitFetcher formId
                    formData
                    (isValid formData.fields)
                    (userMsg
                        |> Maybe.map
                            (\toUserMsg ->
                                toUserMsg { fields = formData.fields }
                            )
                    )
            )


{-| -}
map : (a -> b) -> Msg a -> Msg b
map mapFn msg =
    case msg of
        UserMsg userMsg ->
            UserMsg (mapFn userMsg)

        Submit info ->
            Submit info

        SubmitIfValid formId info isValid toUserMsg ->
            SubmitIfValid formId info isValid (Maybe.map mapFn toUserMsg)

        SubmitFetcher formId info isValid toUserMsg ->
            SubmitFetcher formId info isValid (Maybe.map mapFn toUserMsg)

        FormFieldEvent value ->
            FormFieldEvent value

        NoOp ->
            NoOp
