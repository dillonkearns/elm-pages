module FormDecoder exposing (formDataOnSubmit)

import Html
import Html.Events
import Json.Decode as Decode
import Json.Encode


formDataOnSubmit : Html.Attribute (List ( String, String ))
formDataOnSubmit =
    Html.Events.preventDefaultOn "submit"
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
            |> Decode.map alwaysPreventDefault
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
