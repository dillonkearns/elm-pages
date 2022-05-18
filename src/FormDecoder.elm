module FormDecoder exposing (FormData, Method(..), encodeFormData, formDataOnSubmit, methodToString)

import Html
import Html.Events
import Json.Decode as Decode
import Json.Encode
import Url


type alias FormData =
    { fields : List ( String, String )
    , method : Method
    , action : String
    }


type Method
    = Get
    | Post


formDataOnSubmit : Html.Attribute FormData
formDataOnSubmit =
    Html.Events.preventDefaultOn "submit"
        (Decode.map3 FormData
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
            |> Decode.map alwaysPreventDefault
        )


methodDecoder : Decode.Decoder Method
methodDecoder =
    Decode.string
        |> Decode.map
            (\methodString ->
                case methodString |> String.toUpper of
                    "GET" ->
                        Get

                    "POST" ->
                        Post

                    _ ->
                        -- TODO what about "dialog" method? Is it okay for that to be interpreted as GET,
                        -- or should there be a variant for that?
                        Get
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


methodToString : Method -> String
methodToString method =
    case method of
        Get ->
            "GET"

        Post ->
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
