module Pages.FieldRenderer exposing (Input(..), InputType(..), Options(..), input, inputTypeToString, radio, select, toHtmlProperties)

{-|

@docs Input, InputType, Options, input, inputTypeToString, radio, select, toHtmlProperties

-}

import Html exposing (Html)
import Html.Attributes as Attr
import Json.Encode as Encode


{-| -}
type InputType
    = Text
    | Number
      -- TODO should range have arguments for initial, min, and max?
    | Range
    | Radio
      -- TODO should submit be a special type, or an Input type?
      -- TODO have an option for a submit with a name/value?
    | Date
    | Time
    | Checkbox
    | Tel
    | Search
    | Password
    | Email
    | Url
    | Textarea


{-| -}
inputTypeToString : InputType -> String
inputTypeToString inputType =
    case inputType of
        Text ->
            "text"

        Textarea ->
            "text"

        Number ->
            "number"

        Range ->
            "range"

        Radio ->
            "radio"

        Date ->
            "date"

        Time ->
            "time"

        Checkbox ->
            "checkbox"

        Tel ->
            "tel"

        Search ->
            "search"

        Password ->
            "password"

        Email ->
            "email"

        Url ->
            "url"


{-| -}
type Input
    = Input InputType


{-| -}
type Options a
    = Options (String -> Maybe a) (List String)


{-| -}
input :
    List (Html.Attribute msg)
    ->
        { input
            | value : Maybe String
            , name : String
            , kind : ( Input, List ( String, Encode.Value ) )
        }
    -> Html msg
input attrs rawField =
    case rawField.kind of
        ( Input Textarea, properties ) ->
            Html.textarea
                (attrs
                    ++ toHtmlProperties properties
                    ++ [ Attr.value (rawField.value |> Maybe.withDefault "")
                       , Attr.name rawField.name
                       ]
                )
                []

        ( Input inputType, properties ) ->
            Html.input
                (attrs
                    ++ toHtmlProperties properties
                    ++ [ (case inputType of
                            Checkbox ->
                                Attr.checked ((rawField.value |> Maybe.withDefault "") == "on")

                            _ ->
                                Attr.value (rawField.value |> Maybe.withDefault "")
                          -- TODO is this an okay default?
                         )
                       , Attr.name rawField.name
                       , inputType |> inputTypeToString |> Attr.type_
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
            , String
            )
        )
    ->
        { input
            | value : Maybe String
            , name : String
            , kind : ( Options parsed, List ( String, Encode.Value ) )
        }
    -> Html msg
select selectAttrs enumToOption rawField =
    let
        (Options parseValue possibleValues) =
            rawField.kind |> Tuple.first
    in
    Html.select
        (selectAttrs
            ++ [ Attr.value (rawField.value |> Maybe.withDefault "")
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
                                ( optionAttrs, content ) =
                                    enumToOption justParsed
                            in
                            Html.option (Attr.value possibleValue :: optionAttrs) [ Html.text content ]
                                |> Just

                        Nothing ->
                            Nothing
                )
        )


{-| -}
radio :
    List (Html.Attribute msg)
    ->
        (parsed
         -> (List (Html.Attribute msg) -> Html msg)
         -> Html msg
        )
    ->
        { input
            | value : Maybe String
            , name : String
            , kind : ( Options parsed, List ( String, Encode.Value ) )
        }
    -> Html msg
radio selectAttrs enumToOption rawField =
    let
        (Options parseValue possibleValues) =
            rawField.kind |> Tuple.first
    in
    Html.fieldset
        (selectAttrs
            ++ [ Attr.value (rawField.value |> Maybe.withDefault "")
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
                                renderedElement : Html msg
                                renderedElement =
                                    enumToOption justParsed
                                        (\userHtmlAttrs ->
                                            Html.input
                                                ([ Attr.type_ "radio"
                                                 , Attr.value possibleValue
                                                 , Attr.name rawField.name
                                                 , Attr.checked (rawField.value == Just possibleValue)
                                                 ]
                                                    ++ userHtmlAttrs
                                                )
                                                []
                                        )
                            in
                            Just renderedElement

                        Nothing ->
                            Nothing
                )
        )


{-| -}
toHtmlProperties : List ( String, Encode.Value ) -> List (Html.Attribute msg)
toHtmlProperties properties =
    properties
        |> List.map
            (\( key, value ) ->
                Attr.property key value
            )
