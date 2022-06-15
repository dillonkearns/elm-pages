module Pages.FieldRenderer exposing (..)

{-| -}

import Html exposing (Html)
import Html.Attributes as Attr


type InputType
    = Text
    | Checkbox


type Input
    = Input InputType


type Select a
    = Select (String -> Maybe a) (List String)


{-| -}
input :
    List (Html.Attribute msg)
    ->
        { input
            | value : Maybe String
            , name : String
            , kind : Input
        }
    -> Html msg
input attrs rawField =
    case rawField.kind of
        Input inputType ->
            case inputType of
                Text ->
                    Html.input
                        (attrs
                            ++ [ Attr.value (rawField.value |> Maybe.withDefault "") -- TODO is this an okay default?
                               , Attr.name rawField.name
                               ]
                        )
                        []

                Checkbox ->
                    Html.input
                        (attrs
                            ++ [ Attr.checked ((rawField.value |> Maybe.withDefault "") == "on")
                               , Attr.name rawField.name
                               , Attr.type_ "checkbox"
                               ]
                        )
                        []


{-| -}
select :
    List (Html.Attribute msg)
    ->
        (parsed
         ->
            ( List (Html.Attribute msg)
            , List (Html.Html msg)
            )
        )
    ->
        { input
            | value : Maybe String
            , name : String
            , kind : Select parsed
        }
    -> Html msg
select selectAttrs enumToOption rawField =
    let
        (Select parseValue possibleValues) =
            rawField.kind
    in
    Html.select
        (selectAttrs
            -- TODO need to handle other input types like checkbox
            ++ [ Attr.value (rawField.value |> Maybe.withDefault "") -- TODO is this an okay default?
               , Attr.name rawField.name
               ]
        )
        (possibleValues
            |> List.filterMap
                (\possibleValue ->
                    let
                        parsed : Maybe parsed
                        parsed =
                            possibleValue
                                |> parseValue
                    in
                    case parsed of
                        Just justParsed ->
                            let
                                ( optionAttrs, children ) =
                                    enumToOption justParsed
                            in
                            Html.option (Attr.value possibleValue :: optionAttrs) children
                                |> Just

                        Nothing ->
                            Nothing
                )
        )
