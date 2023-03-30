module Pages.FormState exposing (FieldState, FormState, listeners)

import Dict exposing (Dict)
import Form.FieldStatus exposing (FieldStatus)
import Html exposing (Attribute)
import Html.Attributes as Attr
import Html.Events
import Internal.FieldEvent exposing (Event(..), FieldEvent)
import Json.Decode as Decode exposing (Decoder)


{-| -}
listeners : String -> List (Attribute FieldEvent)
listeners formId =
    [ Html.Events.on "focusin" fieldEventDecoder
    , Html.Events.on "focusout" fieldEventDecoder
    , Html.Events.on "input" fieldEventDecoder
    , Attr.id formId
    ]


{-| -}
fieldEventDecoder : Decoder FieldEvent
fieldEventDecoder =
    Decode.map4 FieldEvent
        inputValueDecoder
        (Decode.at [ "currentTarget", "id" ] Decode.string)
        (Decode.at [ "target", "name" ] Decode.string
            |> Decode.andThen
                (\name ->
                    if name == "" then
                        Decode.fail "Events only run on fields with names."

                    else
                        Decode.succeed name
                )
        )
        fieldDecoder


{-| -}
inputValueDecoder : Decoder String
inputValueDecoder =
    Decode.at [ "target", "type" ] Decode.string
        |> Decode.andThen
            (\targetType ->
                case targetType of
                    "button" ->
                        Decode.fail "Input and focus events don't run on buttons."

                    "checkbox" ->
                        Decode.map2
                            (\valueWhenChecked isChecked ->
                                if isChecked then
                                    valueWhenChecked

                                else
                                    ""
                            )
                            (Decode.at [ "target", "value" ] Decode.string)
                            (Decode.at [ "target", "checked" ] Decode.bool)

                    _ ->
                        Decode.at [ "target", "value" ] Decode.string
            )


{-| -}
fieldDecoder : Decoder Event
fieldDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "input" ->
                        inputValueDecoder |> Decode.map InputEvent

                    "focusin" ->
                        FocusEvent
                            |> Decode.succeed

                    "focusout" ->
                        BlurEvent
                            |> Decode.succeed

                    _ ->
                        Decode.fail "Unexpected event.type"
            )


{-| -}
type alias FormState =
    { fields : Dict String FieldState
    , submitAttempted : Bool
    }


{-| -}
type alias FieldState =
    { value : String
    , status : FieldStatus
    }
