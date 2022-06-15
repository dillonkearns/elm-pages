module Pages.Field exposing (Field(..), FieldInfo, No(..), Yes(..), checkbox, exactValue, int, required, text, withClientValidation, withInitialValue, select)

{-|

@docs Field, FieldInfo, No, Yes, checkbox, exactValue, int, required, text, withClientValidation, withInitialValue, select

-}

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Form.Value
import Json.Encode as Encode
import Pages.FieldRenderer as FieldRenderer exposing (Input(..), Select(..))


{-| -}
type Field error parsed data kind constraints
    = Field (FieldInfo error parsed data) kind


{-| -}
type alias FieldInfo error parsed data =
    { initialValue : Maybe (data -> String)
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List error)
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
            data
            kind
            { constraints
                | required : ()
                , wasMapped : No
            }
    -> Field error parsed data kind { constraints | wasMapped : No }
required missingError (Field field kind) =
    Field
        { initialValue = field.initialValue
        , type_ = field.type_
        , required = True
        , serverValidation = field.serverValidation
        , decode =
            \rawValue ->
                let
                    ( parsed, allErrors ) =
                        field.decode rawValue

                    isEmpty : Bool
                    isEmpty =
                        rawValue == Just "" || rawValue == Nothing
                in
                ( parsed |> Maybe.andThen identity
                , if isEmpty then
                    missingError :: allErrors

                  else
                    allErrors
                )
        , properties = field.properties
        }
        kind


{-| -}
text :
    Field
        error
        (Maybe String)
        data
        Input
        { required : ()
        , plainText : ()
        , wasMapped : No
        , initial : String
        }
text =
    Field
        { initialValue = Nothing
        , type_ = "text"
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
        (FieldRenderer.Input FieldRenderer.Text)


{-| -}
select :
    List ( String, option )
    -> (String -> error)
    ->
        Field
            error
            (Maybe option)
            data
            (Select option)
            { required : ()
            , plainText : ()
            , wasMapped : No
            , initial : String
            }
select optionsMapping invalidError =
    let
        dict : Dict String option
        dict =
            Dict.fromList optionsMapping

        toString a =
            case optionsMapping |> List.filter (\( str, b ) -> b == a) |> List.head of
                Just ( str, b ) ->
                    str

                Nothing ->
                    "Missing enum"

        fromString : String -> Maybe option
        fromString string =
            Dict.get string dict
    in
    Field
        { initialValue = Nothing
        , type_ = "select"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawValue ->
                case rawValue of
                    Nothing ->
                        ( Nothing, [] )

                    Just "" ->
                        ( Nothing, [] )

                    Just justValue ->
                        let
                            parsed : Maybe option
                            parsed =
                                fromString justValue
                        in
                        case parsed of
                            Just okParsed ->
                                ( Just (Just okParsed)
                                , []
                                )

                            Nothing ->
                                ( Just Nothing
                                , [ invalidError justValue
                                  ]
                                )
        , properties = []
        }
        (Select fromString (optionsMapping |> List.map Tuple.first))


{-| -}
exactValue :
    String
    -> error
    ->
        Field
            error
            String
            data
            Input
            { required : ()
            , plainText : ()
            , wasMapped : No
            , initial : String
            }
exactValue initialValue error =
    Field
        { initialValue = Just (\_ -> initialValue)
        , type_ = "text"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawValue ->
                if rawValue == Just initialValue then
                    ( rawValue, [] )

                else
                    ( rawValue, [ error ] )
        , properties = []
        }
        (FieldRenderer.Input FieldRenderer.Text)


{-| -}
checkbox :
    Field
        error
        Bool
        data
        Input
        { required : ()
        }
checkbox =
    Field
        { initialValue = Nothing
        , type_ = "checkbox"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawString ->
                ( (rawString == Just "on")
                    |> Just
                , []
                )
        , properties = []
        }
        (FieldRenderer.Input FieldRenderer.Checkbox)


{-| -}
int :
    { invalid : String -> error }
    ->
        Field
            error
            (Maybe Int)
            data
            Input
            { min : Int
            , max : Int
            , required : ()
            , wasMapped : No
            , initial : Int
            }
int toError =
    Field
        { initialValue = Nothing
        , type_ = "number"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawString ->
                case rawString of
                    Nothing ->
                        ( Nothing, [] )

                    Just "" ->
                        ( Nothing, [] )

                    Just string ->
                        case string |> String.toInt of
                            Just parsedInt ->
                                ( Just (Just parsedInt), [] )

                            Nothing ->
                                ( Nothing, [ toError.invalid string ] )
        , properties = []
        }
        (FieldRenderer.Input FieldRenderer.Text)


{-| -}
withClientValidation : (parsed -> ( Maybe mapped, List error )) -> Field error parsed data kind constraints -> Field error mapped data kind { constraints | wasMapped : Yes }
withClientValidation mapFn (Field field kind) =
    Field
        { initialValue = field.initialValue
        , type_ = field.type_
        , required = field.required
        , serverValidation = field.serverValidation
        , decode =
            \value ->
                value
                    |> field.decode
                    |> (\( maybeValue, errors ) ->
                            case maybeValue of
                                Nothing ->
                                    ( Nothing, errors )

                                Just okValue ->
                                    okValue
                                        |> mapFn
                                        |> Tuple.mapSecond ((++) errors)
                       )
        , properties = field.properties
        }
        kind


{-| -}
withInitialValue : (data -> Form.Value.Value valueType) -> Field error value data kind { constraints | initial : valueType } -> Field error value data kind constraints
withInitialValue toInitialValue (Field field kind) =
    Field
        { field
            | initialValue =
                Just (toInitialValue >> Form.Value.toString)
        }
        kind
