module Form exposing (..)

import Html exposing (Html)
import Html.Attributes as Attr
import Server.Request as Request exposing (Request)


type Form value
    = Form (List FieldInfo) (Request value)


type Field
    = Field FieldInfo


type alias FieldInfo =
    { name : String
    , label : String
    , initialValue : Maybe String
    , type_ : String
    }


succeed : constructor -> Form constructor
succeed constructor =
    Form [] (Request.succeed constructor)


input : { name : String, label : String } -> Field
input { name, label } =
    Field
        { name = name
        , label = label
        , initialValue = Nothing
        , type_ = "text"
        }


number : { name : String, label : String } -> Field
number { name, label } =
    Field
        { name = name
        , label = label
        , initialValue = Nothing
        , type_ = "number"
        }


type_ : String -> Field -> Field
type_ typeName (Field field) =
    Field
        { field | type_ = typeName }


withInitialValue : String -> Field -> Field
withInitialValue initialValue (Field field) =
    Field { field | initialValue = Just initialValue }


required : Field -> Form (String -> form) -> Form form
required (Field field) (Form fields decoder) =
    Form (field :: fields)
        (decoder
            |> Request.andMap (Request.formField_ field.name)
        )



{-
   - If there is at least one file field, then use enctype multi-part. Otherwise use form encoding (or maybe GET with query params?).
   - Should it ever use GET forms?
   - Ability to do server-only validations (like uniqueness check with DataSource)
   - Return error messages that can be presented inline from server response (both on full page load and on client-side request)
   - Add functions for built-in form validations
-}


toHtml : Form value -> Html msg
toHtml (Form fields decoder) =
    Html.form
        [ Attr.method "POST"
        ]
        ((fields
            |> List.reverse
            |> List.map
                (\field ->
                    Html.label
                        []
                        [ Html.text field.label
                        , Html.input
                            ([ Attr.name field.name |> Just
                             , field.initialValue |> Maybe.map Attr.value
                             , field.type_ |> Attr.type_ |> Just
                             , Attr.min "1900" |> Just
                             , Attr.max "2099" |> Just
                             , Attr.required True |> Just
                             ]
                                |> List.filterMap identity
                            )
                            []
                        ]
                )
         )
            ++ [ Html.input [ Attr.type_ "submit" ] []
               ]
        )


toRequest : Form value -> Request value
toRequest (Form fields decoder) =
    Request.expectFormPost
        (\_ ->
            decoder
        )
