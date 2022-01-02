module Form exposing (..)

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Server.Request as Request exposing (Request)


type Form value
    = Form (List FieldInfo) (Request value) (Request (DataSource (List ( String, List String ))))


type Field
    = Field FieldInfo


type alias FieldInfo =
    { name : String
    , label : String
    , initialValue : Maybe String
    , type_ : String
    , min : Maybe String
    , max : Maybe String
    , serverValidation : String -> DataSource (List String)
    }


succeed : constructor -> Form constructor
succeed constructor =
    Form []
        (Request.succeed constructor)
        (Request.succeed (DataSource.succeed []))


input : { name : String, label : String } -> Field
input { name, label } =
    Field
        { name = name
        , label = label
        , initialValue = Nothing
        , type_ = "text"
        , min = Nothing
        , max = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        }


number : { name : String, label : String } -> Field
number { name, label } =
    Field
        { name = name
        , label = label
        , initialValue = Nothing
        , type_ = "number"
        , min = Nothing
        , max = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        }


date : { name : String, label : String } -> Field
date { name, label } =
    Field
        { name = name
        , label = label
        , initialValue = Nothing
        , type_ = "date"
        , min = Nothing
        , max = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        }


withMin : Int -> Field -> Field
withMin min (Field field) =
    Field { field | min = min |> String.fromInt |> Just }


withMax : Int -> Field -> Field
withMax max (Field field) =
    Field { field | max = max |> String.fromInt |> Just }


withMinDate : String -> Field -> Field
withMinDate min (Field field) =
    Field { field | min = min |> Just }


withMaxDate : String -> Field -> Field
withMaxDate max (Field field) =
    Field { field | max = max |> Just }


type_ : String -> Field -> Field
type_ typeName (Field field) =
    Field
        { field | type_ = typeName }


withInitialValue : String -> Field -> Field
withInitialValue initialValue (Field field) =
    Field { field | initialValue = Just initialValue }


withServerValidation : (String -> DataSource (List String)) -> Field -> Field
withServerValidation serverValidation (Field field) =
    Field
        { field
            | serverValidation = serverValidation
        }


required : Field -> Form (String -> form) -> Form form
required (Field field) (Form fields decoder serverValidations) =
    let
        thing : Request (DataSource (List ( String, List String )))
        thing =
            Request.map2
                (\arg1 arg2 ->
                    arg1
                        |> DataSource.map2 (::)
                            (field.serverValidation arg2
                                |> DataSource.map
                                    (\validationErrors ->
                                        ( field.name, validationErrors )
                                    )
                            )
                )
                serverValidations
                (Request.formField_ field.name)
    in
    Form (field :: fields)
        (decoder
            |> Request.andMap (Request.formField_ field.name)
        )
        thing



{-
   - If there is at least one file field, then use enctype multi-part. Otherwise use form encoding (or maybe GET with query params?).
   - Should it ever use GET forms?
   - Ability to do server-only validations (like uniqueness check with DataSource)
   - Return error messages that can be presented inline from server response (both on full page load and on client-side request)
   - Add functions for built-in form validations
-}


toHtml : Dict String (List String) -> Form value -> Html msg
toHtml serverValidationErrors (Form fields decoder serverValidations) =
    Html.form
        [ Attr.method "POST"
        ]
        ((fields
            |> List.reverse
            |> List.map
                (\field ->
                    Html.div []
                        [ case serverValidationErrors |> Dict.get field.name of
                            Just (first :: rest) ->
                                Html.ul
                                    [ Attr.style "border" "solid red"
                                    ]
                                    (List.map
                                        (\error ->
                                            Html.li []
                                                [ Html.text error
                                                ]
                                        )
                                        (first :: rest)
                                    )

                            _ ->
                                Html.span []
                                    []
                        , Html.label
                            []
                            [ Html.text field.label
                            , Html.input
                                ([ Attr.name field.name |> Just
                                 , field.initialValue |> Maybe.map Attr.value
                                 , field.type_ |> Attr.type_ |> Just
                                 , field.min |> Maybe.map Attr.min
                                 , field.max |> Maybe.map Attr.max
                                 , Attr.required True |> Just
                                 ]
                                    |> List.filterMap identity
                                )
                                []
                            ]
                        ]
                )
         )
            ++ [ Html.input [ Attr.type_ "submit" ] []
               ]
        )


toRequest : Form value -> Request value
toRequest (Form fields decoder serverValidations) =
    Request.expectFormPost
        (\_ ->
            decoder
        )


toRequest2 : Form value -> Request (DataSource (Result (Dict String (List String)) value))
toRequest2 (Form fields decoder serverValidations) =
    Request.map2
        (\decoded errors ->
            errors
                |> DataSource.map
                    (\validationErrors ->
                        if validationErrors |> List.isEmpty then
                            Ok decoded

                        else
                            validationErrors
                                |> Dict.fromList
                                |> Err
                    )
        )
        (Request.expectFormPost
            (\_ ->
                decoder
            )
        )
        (Request.expectFormPost
            (\_ ->
                serverValidations
            )
        )
