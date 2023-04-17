module Pages.Internal.Msg exposing
    (  Msg(..)
       --, fetcherOnSubmit

    ,  map
       --, onSubmit
       --, submitIfValid

    )

--import Form.FormData exposing (FormData)
--import FormDecoder

import Form exposing (Method)
import Html exposing (Attribute)
import Html.Attributes as Attr
import Json.Decode


{-| -}
type Msg userMsg
    = UserMsg userMsg
    | Submit { valid : Bool, method : Method, action : String, fields : List ( String, String ), id : String, msg : Maybe userMsg, useFetcher : Bool }
      --| SubmitIfValid String FormData Bool (Maybe userMsg)
      --| SubmitFetcher String FormData Bool (Maybe userMsg)
    | FormMsg (Form.Msg (Msg userMsg))
    | NoOp



--{-| -}
--onSubmit : Attribute (Msg userMsg)
--onSubmit =
--    FormDecoder.formDataOnSubmit
--        |> Attr.map Submit
--
--
--{-| -}
--submitIfValid : Maybe ({ fields : List ( String, String ) } -> userMsg) -> String -> (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
--submitIfValid userMsg formId isValid =
--    FormDecoder.formDataOnSubmit
--        |> Attr.map
--            (\formData ->
--                SubmitIfValid formId
--                    formData
--                    (isValid formData.fields)
--                    (userMsg
--                        |> Maybe.map
--                            (\toUserMsg ->
--                                toUserMsg { fields = formData.fields }
--                            )
--                    )
--            )
--
--
--
--{-| -}
--fetcherOnSubmit : Maybe ({ fields : List ( String, String ) } -> userMsg) -> String -> (List ( String, String ) -> Bool) -> Attribute (Msg userMsg)
--fetcherOnSubmit userMsg formId isValid =
--    FormDecoder.formDataOnSubmit
--        |> Attr.map
--            (\formData ->
--                SubmitFetcher formId
--                    formData
--                    (isValid formData.fields)
--                    (userMsg
--                        |> Maybe.map
--                            (\toUserMsg ->
--                                toUserMsg { fields = formData.fields }
--                            )
--                    )
--            )


{-| -}
map : (a -> b) -> Msg a -> Msg b
map mapFn msg =
    case msg of
        UserMsg userMsg ->
            UserMsg (mapFn userMsg)

        Submit info ->
            Submit
                { valid = info.valid
                , fields = info.fields
                , action = info.action
                , id = info.id
                , msg = Maybe.map mapFn info.msg
                , method = info.method
                , useFetcher = info.useFetcher
                }

        FormMsg value ->
            FormMsg
                (Form.mapMsg (map mapFn) value)

        NoOp ->
            NoOp
