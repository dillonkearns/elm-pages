module FormDecoder exposing (encodeFormData, formDataOnSubmit, methodToString)

import Form.FormData as FormData exposing (FormData)
import Html
import Html.Events
import Json.Decode as Decode
import Json.Encode
import Url


formDataOnSubmit : Html.Attribute FormData
formDataOnSubmit =
    Html.Events.preventDefaultOn "submit"
        (Decode.map4 FormData
            (Decode.value
                |> Decode.andThen
                    (\decodeValue ->
                        case Decode.decodeValue tuplesDecoder (decoder decodeValue) of
                            Ok decoded ->
                                Decode.succeed decoded

                            Err error ->
                                Decode.succeed
                                    [ ( "error"
                                      , Decode.errorToString error
                                      )
                                    ]
                    )
            )
            (Decode.at [ "submitter", "form", "method" ] methodDecoder)
            (Decode.at [ "submitter", "form", "action" ] Decode.string)
            (Decode.at [ "submitter", "form", "id" ] (Decode.nullable Decode.string))
            |> Decode.map alwaysPreventDefault
        )


methodDecoder : Decode.Decoder FormData.Method
methodDecoder =
    Decode.string
        |> Decode.map
            (\methodString ->
                case methodString |> String.toUpper of
                    "GET" ->
                        FormData.Get

                    "POST" ->
                        FormData.Post

                    _ ->
                        -- TODO what about "dialog" method? Is it okay for that to be interpreted as GET,
                        -- or should there be a variant for that?
                        FormData.Get
            )


decoder : Decode.Value -> Decode.Value
decoder event =
    Json.Encode.string "REPLACE_ME_WITH_FORM_TO_STRING"


alwaysPreventDefault : msg -> ( msg, Bool )
alwaysPreventDefault msg =
    ( msg, True )


tuplesDecoder : Decode.Decoder (List ( String, String ))
tuplesDecoder =
    Decode.list
        (Decode.map2 Tuple.pair
            (Decode.index 0 Decode.string)
            (Decode.index 1 Decode.string)
        )


methodToString : FormData.Method -> String
methodToString method =
    case method of
        FormData.Get ->
            "GET"

        FormData.Post ->
            "POST"


encodeFormData :
    FormData
    -> String
encodeFormData data =
    data.fields
        |> List.map
            (\( name, value ) ->
                Url.percentEncode name ++ "=" ++ Url.percentEncode value
            )
        |> String.join "&"
