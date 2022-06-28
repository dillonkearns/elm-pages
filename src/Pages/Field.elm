module Pages.Field exposing
    ( text, checkbox, int, float
    , select, range, OutsideRange(..)
    , date
    , Field(..), FieldInfo, exactValue
    , required, withClientValidation, withInitialValue
    , email, password, search, telephone, url, textarea
    , withMax, withMin, withStep, withMinLength, withMaxLength
    , No(..), Yes(..)
    )

{-|


## Base Fields

@docs text, checkbox, int, float


## Multiple Choice Fields

@docs select, range, OutsideRange


## Date/Time Fields

@docs date


## Other

@docs Field, FieldInfo, exactValue


## Field Configuration

@docs required, withClientValidation, withInitialValue


## Text Field Display Options

@docs email, password, search, telephone, url, textarea


## Numeric Field Options

@docs withMax, withMin, withStep, withMinLength, withMaxLength


## Phantom Options

@docs No, Yes

-}

import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict exposing (Dict)
import Form.Value
import Json.Encode as Encode
import Pages.FieldRenderer as FieldRenderer exposing (Input(..), Options(..))


{-| -}
type Field error parsed data kind constraints
    = Field (FieldInfo error parsed data) kind


{-| -}
type alias FieldInfo error parsed data =
    { initialValue : Maybe (data -> String)
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
        , minlength : ()
        , maxlength : ()
        }
text =
    Field
        { initialValue = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawValue ->
                ( if rawValue == Just "" then
                    Just Nothing

                  else
                    Just rawValue
                , []
                )
        , properties = []
        }
        (FieldRenderer.Input FieldRenderer.Text)


{-| -}
date :
    { invalid : String -> error }
    ->
        Field
            error
            (Maybe Date)
            data
            Input
            { min : Date
            , max : Date
            , required : ()
            , wasMapped : No
            , initial : Date
            }
date toError =
    Field
        { initialValue = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawString ->
                if (rawString |> Maybe.withDefault "") == "" then
                    ( Just Nothing, [] )

                else
                    case
                        rawString
                            |> Maybe.withDefault ""
                            |> Date.fromIsoString
                            |> Result.mapError (\_ -> toError.invalid (rawString |> Maybe.withDefault ""))
                    of
                        Ok parsedDate ->
                            ( Just (Just parsedDate), [] )

                        Err error ->
                            ( Nothing, [ error ] )
        , properties = []
        }
        (FieldRenderer.Input FieldRenderer.Date)


{-| -}
select :
    List ( String, option )
    -> (String -> error)
    ->
        Field
            error
            (Maybe option)
            data
            (Options option)
            { required : ()
            , wasMapped : No
            }
select optionsMapping invalidError =
    let
        dict : Dict String option
        dict =
            Dict.fromList optionsMapping

        fromString : String -> Maybe option
        fromString string =
            Dict.get string dict
    in
    Field
        { initialValue = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawValue ->
                case rawValue of
                    Nothing ->
                        ( Just Nothing, [] )

                    Just "" ->
                        ( Just Nothing, [] )

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
        (Options fromString (optionsMapping |> List.map Tuple.first))


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
            , step : Int
            , initial : Int
            }
int toError =
    Field
        { initialValue = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawString ->
                case rawString of
                    Nothing ->
                        ( Just Nothing, [] )

                    Just "" ->
                        ( Just Nothing, [] )

                    Just string ->
                        case string |> String.toInt of
                            Just parsedInt ->
                                ( Just (Just parsedInt), [] )

                            Nothing ->
                                ( Nothing, [ toError.invalid string ] )
        , properties = []
        }
        (FieldRenderer.Input FieldRenderer.Number)


{-| -}
float :
    { invalid : String -> error }
    ->
        Field
            error
            (Maybe Float)
            data
            Input
            { min : Float
            , max : Float
            , required : ()
            , wasMapped : No
            , initial : Float
            }
float toError =
    Field
        { initialValue = Nothing
        , serverValidation = \_ -> DataSource.succeed []
        , decode =
            \rawString ->
                case rawString of
                    Nothing ->
                        ( Just Nothing, [] )

                    Just "" ->
                        ( Just Nothing, [] )

                    Just string ->
                        case string |> String.toFloat of
                            Just parsedFloat ->
                                ( Just (Just parsedFloat), [] )

                            Nothing ->
                                ( Nothing, [ toError.invalid string ] )
        , properties = []
        }
        (FieldRenderer.Input FieldRenderer.Number)


{-| -}
telephone :
    Field error parsed data Input { constraints | plainText : () }
    -> Field error parsed data Input constraints
telephone (Field field kind) =
    Field field
        (FieldRenderer.Input FieldRenderer.Tel)


{-| -}
search :
    Field error parsed data Input { constraints | plainText : () }
    -> Field error parsed data Input constraints
search (Field field kind) =
    Field field
        (FieldRenderer.Input FieldRenderer.Search)


{-| -}
password :
    Field error parsed data Input { constraints | plainText : () }
    -> Field error parsed data Input constraints
password (Field field kind) =
    Field field
        (FieldRenderer.Input FieldRenderer.Password)


{-| -}
email :
    Field error parsed data Input { constraints | plainText : () }
    -> Field error parsed data Input constraints
email (Field field kind) =
    Field field
        (FieldRenderer.Input FieldRenderer.Email)


{-| -}
url :
    Field error parsed data Input { constraints | plainText : () }
    -> Field error parsed data Input constraints
url (Field field kind) =
    Field field
        (FieldRenderer.Input FieldRenderer.Url)


{-| -}
textarea :
    Field error parsed data Input { constraints | plainText : () }
    -> Field error parsed data Input constraints
textarea (Field field kind) =
    Field field (FieldRenderer.Input FieldRenderer.Textarea)


{-| -}
type OutsideRange
    = AboveRange
    | BelowRange


{-| -}
range :
    { min : Form.Value.Value valueType
    , max : Form.Value.Value valueType
    , initial : data -> Form.Value.Value valueType
    , missing : error
    , invalid : OutsideRange -> error
    }
    ->
        Field
            error
            (Maybe valueType)
            data
            kind
            { constraints
                | required : ()
                , initial : valueType
                , min : valueType
                , max : valueType
                , wasMapped : No
            }
    ->
        Field
            error
            valueType
            data
            Input
            { constraints | wasMapped : No }
range info field =
    field
        |> required info.missing
        |> withMin info.min (info.invalid BelowRange)
        |> withMax info.max (info.invalid AboveRange)
        |> (\(Field innerField _) -> Field { innerField | initialValue = Just (info.initial >> Form.Value.toString) } (FieldRenderer.Input FieldRenderer.Range))


validateRequiredField : { toError | missing : error } -> Maybe String -> Result error String
validateRequiredField toError maybeRaw =
    if (maybeRaw |> Maybe.withDefault "") == "" then
        Err toError.missing

    else
        Ok (maybeRaw |> Maybe.withDefault "")


{-| -}
withClientValidation : (parsed -> ( Maybe mapped, List error )) -> Field error parsed data kind constraints -> Field error mapped data kind { constraints | wasMapped : Yes }
withClientValidation mapFn (Field field kind) =
    Field
        { initialValue = field.initialValue
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



-- Input Properties


{-| -}
withMin : Form.Value.Value valueType -> error -> Field error parsed data kind { constraints | min : valueType } -> Field error parsed data kind constraints
withMin min error (Field field kind) =
    Field
        { initialValue = field.initialValue
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
                                    if isEmptyValue value then
                                        ( Just okValue, errors )

                                    else
                                        case Form.Value.compare (value |> Maybe.withDefault "") min of
                                            LT ->
                                                ( Just okValue, error :: errors )

                                            _ ->
                                                ( Just okValue, errors )
                       )
        , properties = ( "min", Encode.string (Form.Value.toString min) ) :: field.properties
        }
        kind


{-| -}
withMinLength : Int -> error -> Field error parsed data kind { constraints | minlength : () } -> Field error parsed data kind constraints
withMinLength minLength error (Field field kind) =
    Field
        { initialValue = field.initialValue
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
                                    if (value |> Maybe.withDefault "" |> String.length) >= minLength then
                                        ( Just okValue, errors )

                                    else
                                        ( Just okValue, error :: errors )
                       )
        , properties = ( "minlength", Encode.string (String.fromInt minLength) ) :: field.properties
        }
        kind


{-| -}
withMaxLength : Int -> error -> Field error parsed data kind { constraints | maxlength : () } -> Field error parsed data kind constraints
withMaxLength maxLength error (Field field kind) =
    Field
        { initialValue = field.initialValue
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
                                    if (value |> Maybe.withDefault "" |> String.length) <= maxLength then
                                        ( Just okValue, errors )

                                    else
                                        ( Just okValue, error :: errors )
                       )
        , properties = ( "maxlength", Encode.string (String.fromInt maxLength) ) :: field.properties
        }
        kind


isEmptyValue : Maybe String -> Bool
isEmptyValue value =
    (value |> Maybe.withDefault "") == ""


{-| -}
withMax : Form.Value.Value valueType -> error -> Field error parsed data kind { constraints | max : valueType } -> Field error parsed data kind constraints
withMax max error (Field field kind) =
    Field
        { initialValue = field.initialValue
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
                                    if isEmptyValue value then
                                        ( Just okValue, errors )

                                    else
                                        case Form.Value.compare (value |> Maybe.withDefault "") max of
                                            GT ->
                                                ( Just okValue, error :: errors )

                                            _ ->
                                                ( Just okValue, errors )
                       )
        , properties = ( "max", Encode.string (Form.Value.toString max) ) :: field.properties
        }
        kind


{-| -}
withStep : Form.Value.Value valueType -> Field msg error value view { constraints | step : valueType } -> Field msg error value view constraints
withStep max field =
    withStringProperty ( "step", Form.Value.toString max ) field


withStringProperty : ( String, String ) -> Field error parsed data kind constraints1 -> Field error parsed data kind constraints2
withStringProperty ( key, value ) (Field field kind) =
    Field
        { field | properties = ( key, Encode.string value ) :: field.properties }
        kind
