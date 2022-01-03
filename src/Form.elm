module Form exposing (..)

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Server.Request as Request exposing (Request)


type Form value
    = Form
        (List FieldInfo)
        (Request value)
        (Request
            (DataSource
                (List
                    ( String
                    , { errors : List String
                      , raw : String
                      }
                    )
                )
            )
        )


type Field
    = Field FieldInfo


type alias FieldInfo =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , min : Maybe String
    , max : Maybe String
    , serverValidation : String -> DataSource (List String)
    , toHtml :
        FinalFieldInfo
        -> Html Never
    }


type alias FinalFieldInfo =
    { name : String
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


toInputRecord :
    String
    -> FinalFieldInfo
    ->
        { toInput : List (Html.Attribute Never) -> Html Never
        , toLabel : List (Html.Attribute Never) -> List (Html Never) -> Html Never
        }
toInputRecord name field =
    { toInput =
        \attrs ->
            Html.input
                (([ Attr.name name |> Just
                  , field.initialValue |> Maybe.map Attr.value
                  , field.type_ |> Attr.type_ |> Just
                  , field.min |> Maybe.map Attr.min
                  , field.max |> Maybe.map Attr.max
                  , Attr.required True |> Just
                  ]
                    |> List.filterMap identity
                 )
                    ++ attrs
                )
                []
    , toLabel =
        \attributes children ->
            Html.label (Attr.for name :: attributes) children
    }


input :
    String
    ->
        ({ toInput : List (Html.Attribute Never) -> Html Never
         , toLabel : List (Html.Attribute Never) -> List (Html Never) -> Html Never
         }
         -> Html Never
        )
    -> Field
input name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "text"
        , min = Nothing
        , max = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo ->
                toHtmlFn (toInputRecord name fieldInfo)
        }



--number : { name : String, label : String } -> Field
--number { name, label } =
--    Field
--        { name = name
--        , label = label
--        , initialValue = Nothing
--        , type_ = "number"
--        , min = Nothing
--        , max = Nothing
--        , serverValidation = \_ -> DataSource.succeed []
--        }


date :
    String
    ->
        ({ toInput : List (Html.Attribute Never) -> Html Never
         , toLabel : List (Html.Attribute Never) -> List (Html Never) -> Html Never
         }
         -> Html Never
        )
    -> Field
date name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "date"
        , min = Nothing
        , max = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo ->
                toHtmlFn (toInputRecord name fieldInfo)
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
        thing : Request (DataSource (List ( String, { raw : String, errors : List String } )))
        thing =
            Request.map2
                (\arg1 arg2 ->
                    arg1
                        |> DataSource.map2 (::)
                            (field.serverValidation arg2
                                |> DataSource.map
                                    (\validationErrors ->
                                        ( field.name
                                        , { errors = validationErrors
                                          , raw = arg2
                                          }
                                        )
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


simplify : FieldInfo -> FinalFieldInfo
simplify field =
    { name = field.name
    , initialValue = field.initialValue
    , type_ = field.type_
    , min = field.min
    , max = field.max
    , serverValidation = field.serverValidation
    }



{-
   - If there is at least one file field, then use enctype multi-part. Otherwise use form encoding (or maybe GET with query params?).
   - Should it ever use GET forms?
   - Ability to do server-only validations (like uniqueness check with DataSource)
   - Return error messages that can be presented inline from server response (both on full page load and on client-side request)
   - Add functions for built-in form validations
-}


toHtml : Dict String { raw : String, errors : List String } -> Form value -> Html msg
toHtml serverValidationErrors (Form fields decoder serverValidations) =
    Html.form
        [ Attr.method "POST"
        ]
        ((fields
            |> List.reverse
            |> List.map
                (\field ->
                    field.toHtml (simplify field)
                        |> Html.map never
                )
         )
            ++ [ Html.input [ Attr.type_ "submit" ] []
               ]
        )



--((fields
--    |> List.reverse
--    |> List.map
--        (\field ->
--            Html.div []
--                [ case serverValidationErrors |> Dict.get field.name of
--                    Just entry ->
--                        let
--                            { raw, errors } =
--                                entry
--                        in
--                        case entry.errors of
--                            first :: rest ->
--                                Html.div []
--                                    [ Html.ul
--                                        [ Attr.style "border" "solid red"
--                                        ]
--                                        (List.map
--                                            (\error ->
--                                                Html.li []
--                                                    [ Html.text error
--                                                    ]
--                                            )
--                                            (first :: rest)
--                                        )
--                                    , Html.label
--                                        []
--                                        [ Html.text field.label
--                                        , Html.input
--                                            ([ Attr.name field.name |> Just
--
--                                             --, field.initialValue |> Maybe.map Attr.value
--                                             , raw |> Attr.value |> Just
--                                             , field.type_ |> Attr.type_ |> Just
--                                             , field.min |> Maybe.map Attr.min
--                                             , field.max |> Maybe.map Attr.max
--                                             , Attr.required True |> Just
--                                             ]
--                                                |> List.filterMap identity
--                                            )
--                                            []
--                                        ]
--                                    ]
--
--                            _ ->
--                                Html.div []
--                                    [ Html.label
--                                        []
--                                        [ Html.text field.label
--                                        , Html.input
--                                            ([ Attr.name field.name |> Just
--
--                                             --, field.initialValue |> Maybe.map Attr.value
--                                             , raw |> Attr.value |> Just
--                                             , field.type_ |> Attr.type_ |> Just
--                                             , field.min |> Maybe.map Attr.min
--                                             , field.max |> Maybe.map Attr.max
--                                             , Attr.required True |> Just
--                                             ]
--                                                |> List.filterMap identity
--                                            )
--                                            []
--                                        ]
--                                    ]
--
--                    Nothing ->
--                        Html.div []
--                            [ Html.label
--                                []
--                                [ Html.text field.label
--                                , Html.input
--                                    ([ Attr.name field.name |> Just
--                                     , field.initialValue |> Maybe.map Attr.value
--                                     , field.type_ |> Attr.type_ |> Just
--                                     , field.min |> Maybe.map Attr.min
--                                     , field.max |> Maybe.map Attr.max
--                                     , Attr.required True |> Just
--                                     ]
--                                        |> List.filterMap identity
--                                    )
--                                    []
--                                ]
--                            ]
--                ]
--        )
-- )
--    ++ [ Html.input [ Attr.type_ "submit" ] []
--       ]
--)


toRequest : Form value -> Request value
toRequest (Form fields decoder serverValidations) =
    Request.expectFormPost
        (\_ ->
            decoder
        )


toRequest2 :
    Form value
    ->
        Request
            (DataSource
                (Result
                    (Dict
                        String
                        { errors : List String
                        , raw : String
                        }
                    )
                    value
                )
            )
toRequest2 (Form fields decoder serverValidations) =
    Request.map2
        (\decoded errors ->
            errors
                |> DataSource.map
                    (\validationErrors ->
                        if hasErrors validationErrors then
                            validationErrors
                                |> Dict.fromList
                                |> Err

                        else
                            Ok decoded
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


hasErrors : List ( String, { errors : List String, raw : String } ) -> Bool
hasErrors validationErrors =
    List.any
        (\( _, entry ) ->
            entry.errors |> List.isEmpty |> not
        )
        validationErrors
