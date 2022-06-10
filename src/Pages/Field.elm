module Pages.Field exposing (..)

import DataSource exposing (DataSource)
import Json.Encode as Encode


type Field error parsed constraints
    = Field (FieldInfo error parsed)


type alias FieldInfo error parsed =
    { --, initialValue : Maybe String
      type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List error)

    --, decode : String -> Form.FormState -> ( Maybe parsed, List error )
    , decode : Maybe String -> ( Maybe parsed, List error )
    , properties : List ( String, Encode.Value )
    }


{-| -}
type Yes
    = Yes Never


{-| -}
type No
    = No Never


{-| -}
required :
    error
    ->
        Field
            error
            (Maybe parsed)
            { constraints
                | required : ()
                , wasMapped : No
            }
    -> Field error parsed { constraints | wasMapped : No }
required missingError (Field field) =
    Field
        { type_ = field.type_
        , required = True
        , serverValidation = field.serverValidation
        , decode =
            \rawValue ->
                case field.decode rawValue of
                    ( Just decoded, errors ) ->
                        ( decoded, errors )

                    ( Nothing, errors ) ->
                        ( Nothing, missingError :: errors )
        , properties = field.properties
        }


{-| -}
text :
    Field
        error
        (Maybe String)
        { required : ()
        , plainText : ()
        , wasMapped : No
        , initial : String
        }
text =
    Field
        { type_ = "text"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawValue ->
                ( if rawValue == Just "" then
                    Nothing

                  else
                    Just rawValue
                , []
                )
        , properties = []
        }
