module Pages.Form exposing (..)

import Dict exposing (Dict)
import Html exposing (Attribute)
import Html.Attributes
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Pages.Msg


listeners : String -> List (Attribute (Pages.Msg.Msg userMsg))
listeners formId =
    [ Html.Events.on "focusin" (Decode.value |> Decode.map Pages.Msg.FormFieldEvent)
    , Html.Events.on "focusout" (Decode.value |> Decode.map Pages.Msg.FormFieldEvent)
    , Html.Events.on "input" (Decode.value |> Decode.map Pages.Msg.FormFieldEvent)
    , Html.Attributes.id formId
    ]


type Event
    = InputEvent String
    | FocusEvent
      --| ChangeEvent
    | BlurEvent


type alias FieldEvent =
    { formId : String
    , name : String
    , event : Event
    }


fieldEventDecoder : Decoder FieldEvent
fieldEventDecoder =
    Decode.map3 FieldEvent
        (Decode.at [ "currentTarget", "id" ] Decode.string)
        (Decode.at [ "target", "name" ] Decode.string)
        fieldDecoder


fieldDecoder : Decoder Event
fieldDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "input" ->
                        Decode.map InputEvent
                            (Decode.at [ "target", "value" ] Decode.string)

                    "focusin" ->
                        FocusEvent
                            |> Decode.succeed

                    "focusout" ->
                        BlurEvent
                            |> Decode.succeed

                    _ ->
                        Decode.fail "Unexpected event.type"
            )


update : Decode.Value -> PageFormState -> PageFormState
update eventObject pageFormState =
    --if Dict.isEmpty pageFormState then
    --    -- TODO get all initial field values
    --    pageFormState
    --
    --else
    case eventObject |> Decode.decodeValue fieldEventDecoder |> Debug.log "fieldEvent" of
        Ok fieldEvent ->
            pageFormState
                |> Dict.update fieldEvent.formId
                    (\previousValue_ ->
                        let
                            previousValue : FormState
                            previousValue =
                                previousValue_
                                    |> Maybe.withDefault Dict.empty
                        in
                        previousValue
                            |> updateForm fieldEvent
                            |> Just
                    )

        Err _ ->
            pageFormState


updateForm : FieldEvent -> FormState -> FormState
updateForm fieldEvent formState =
    formState
        |> Dict.update fieldEvent.name
            (\previousValue_ ->
                let
                    previousValue : FieldState
                    previousValue =
                        previousValue_
                            |> Maybe.withDefault { value = "", status = NotVisited }
                in
                (case fieldEvent.event of
                    InputEvent newValue ->
                        { previousValue | value = newValue |> Debug.log fieldEvent.name }

                    FocusEvent ->
                        previousValue

                    BlurEvent ->
                        previousValue
                )
                    |> Just
            )


type alias PageFormState =
    Dict String FormState


type alias FormState =
    Dict String FieldState


type alias FieldState =
    { value : String
    , status : FieldStatus
    }


type FieldStatus
    = NotVisited
    | Focused
    | Changed
    | Blurred
