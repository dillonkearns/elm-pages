module Form.FieldView exposing
    ( Input(..), InputType(..), Options(..), input, inputTypeToString, radio, toHtmlProperties, Hidden(..)
    , radioStyled, inputStyled
    , selectOld
    )

{-|

@docs Input, InputType, Options, input, inputTypeToString, radio, toHtmlProperties, Hidden


## Html.Styled Helpers

@docs radioStyled, inputStyled


## Need to Migrate to New Validation Form type

@docs selectOld

-}

import Form.Validation
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Styled
import Html.Styled.Attributes as StyledAttr
import Json.Encode as Encode
import Pages.Internal.Form exposing (Validation(..), ViewField)


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


{-| There are no render helpers for hidden fields because the `Form.renderHtml` helper functions automatically render hidden fields for you.
-}
type Hidden
    = Hidden


{-| -}
type Options a
    = Options (String -> Maybe a) (List String)


{-| -}
input :
    List (Html.Attribute msg)
    -> Form.Validation.FieldValidation error parsed Input
    -> Html msg
input attrs (Validation viewField fieldName ( maybeParsed, fieldErrors )) =
    let
        justViewField =
            expectViewField viewField

        rawField =
            { name = fieldName |> Maybe.withDefault ""
            , value = justViewField.value
            , kind = justViewField.kind
            }
    in
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
inputStyled :
    List (Html.Styled.Attribute msg)
    -> Form.Validation.FieldValidation error parsed Input
    -> Html.Styled.Html msg
inputStyled attrs (Validation viewField fieldName ( maybeParsed, fieldErrors )) =
    let
        justViewField =
            expectViewField viewField

        rawField =
            { name = fieldName |> Maybe.withDefault ""
            , value = justViewField.value
            , kind = justViewField.kind
            }
    in
    case rawField.kind of
        ( Input Textarea, properties ) ->
            Html.Styled.textarea
                (attrs
                    ++ (toHtmlProperties properties |> List.map StyledAttr.fromUnstyled)
                    ++ ([ Attr.value (rawField.value |> Maybe.withDefault "")
                        , Attr.name rawField.name
                        ]
                            |> List.map StyledAttr.fromUnstyled
                       )
                )
                []

        ( Input inputType, properties ) ->
            Html.Styled.input
                (attrs
                    ++ (toHtmlProperties properties |> List.map StyledAttr.fromUnstyled)
                    ++ ([ (case inputType of
                            Checkbox ->
                                Attr.checked ((rawField.value |> Maybe.withDefault "") == "on")

                            _ ->
                                Attr.value (rawField.value |> Maybe.withDefault "")
                           -- TODO is this an okay default?
                          )
                        , Attr.name rawField.name
                        , inputType |> inputTypeToString |> Attr.type_
                        ]
                            |> List.map StyledAttr.fromUnstyled
                       )
                )
                []


{-| -}
selectOld :
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
selectOld selectAttrs enumToOption rawField =
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
    -> Form.Validation.FieldValidation error parsed2 (Options parsed)
    -> Html msg
radio selectAttrs enumToOption (Validation viewField fieldName ( maybeParsed, fieldErrors )) =
    let
        justViewField =
            viewField |> expectViewField

        rawField =
            { name = fieldName |> Maybe.withDefault ""
            , value = justViewField.value
            , kind = justViewField.kind
            }

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


expectViewField : Maybe (ViewField kind) -> ViewField kind
expectViewField viewField =
    case viewField of
        Just justViewField ->
            justViewField

        Nothing ->
            expectViewField viewField


{-| -}
radioStyled :
    List (Html.Styled.Attribute msg)
    ->
        (parsed
         -> (List (Html.Styled.Attribute msg) -> Html.Styled.Html msg)
         -> Html.Styled.Html msg
        )
    -> Form.Validation.FieldValidation error parsed2 (Options parsed)
    -> Html.Styled.Html msg
radioStyled selectAttrs enumToOption (Validation viewField fieldName ( maybeParsed, fieldErrors )) =
    let
        justViewField =
            viewField |> expectViewField

        rawField =
            { name = fieldName |> Maybe.withDefault ""
            , value = justViewField.value
            , kind = justViewField.kind
            }

        (Options parseValue possibleValues) =
            rawField.kind |> Tuple.first
    in
    Html.Styled.fieldset
        (selectAttrs
            ++ [ StyledAttr.value (rawField.value |> Maybe.withDefault "")
               , StyledAttr.name rawField.name
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
                                renderedElement : Html.Styled.Html msg
                                renderedElement =
                                    enumToOption justParsed
                                        (\userHtmlAttrs ->
                                            Html.Styled.input
                                                (([ Attr.type_ "radio"
                                                  , Attr.value possibleValue
                                                  , Attr.name rawField.name
                                                  , Attr.checked (rawField.value == Just possibleValue)
                                                  ]
                                                    |> List.map StyledAttr.fromUnstyled
                                                 )
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
