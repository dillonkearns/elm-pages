module Form exposing (..)

import Codec exposing (Codec)
import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict exposing (Dict)
import Dict.Extra
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import List.Extra
import List.NonEmpty
import PageServerResponse exposing (PageServerResponse)
import Server.Request as Request exposing (Request)
import Server.Response
import Task
import Url


type FieldStatus
    = NotVisited
    | Focused
    | Changed
    | Blurred


http : String -> Form error value view -> Model -> Cmd (Result Http.Error (FieldState String))
http url_ (Form fields decoder serverValidations modelToValue) model =
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "accept" "application/json"
            ]
        , body =
            model.fields
                |> Dict.toList
                |> List.map
                    (\( name, { raw } ) ->
                        Url.percentEncode name
                            ++ "="
                            ++ Url.percentEncode
                                (raw |> Maybe.withDefault "")
                    )
                |> String.join "&"
                |> Http.stringBody "application/x-www-form-urlencoded"
        , expect =
            Http.expectJson identity
                (Decode.dict
                    (Decode.map2
                        (\raw errors ->
                            { raw = raw
                            , errors = errors
                            , status = NotVisited
                            }
                        )
                        (Decode.field "raw" (Decode.nullable Decode.string))
                        (Decode.field "errors"
                            (Decode.list
                                (Codec.decoder errorCodec)
                            )
                        )
                    )
                )
        , timeout = Nothing
        , tracker = Nothing
        , url = url_
        }


errorCodec : Codec String
errorCodec =
    Codec.string


type alias RawModel error =
    { fields : List ( String, List error )
    , formErrors : Dict String (List error)
    }


type Form error value view
    = Form
        -- TODO either make this a Dict and include the client-side validations here
        -- OR create a new Dict with ( name => client-side validation ( name -> Result String () )
        (List
            ( List (FieldInfoSimple error view)
            , List view -> List view
            )
        )
        ((String -> Request (Maybe String)) -> Request (Result (List ( String, List error )) ( value, List ( String, List error ) )))
        ((String -> Request (Maybe String))
         ->
            Request
                (DataSource
                    (List
                        ( String
                        , RawFieldState error
                        )
                    )
                )
        )
        (FieldState error -> Result (List ( String, List error )) ( value, List ( String, List error ) ))


type Field error value view constraints
    = Field (FieldInfo error value view)


type alias FormInfo =
    { submitStatus : SubmitStatus
    }


type alias FieldInfoSimple error view =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List error)
    , toHtml :
        FormInfo
        -> Bool
        -> FinalFieldInfo error
        -> Maybe (RawFieldState error)
        -> view
    , properties : List ( String, Encode.Value )
    , clientValidations : Maybe String -> Result (List error) ()
    }


type alias RawFieldState error =
    { raw : Maybe String
    , errors : List error
    , status : FieldStatus
    }


type alias FieldInfo error value view =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List error)
    , toHtml :
        FormInfo
        -> Bool
        -> FinalFieldInfo error
        -> Maybe (RawFieldState error)
        -> view
    , decode : Maybe String -> Result (List error) ( value, List error )
    , properties : List ( String, Encode.Value )
    }


type alias FinalFieldInfo error =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List error)
    , properties : List ( String, Encode.Value )
    }


succeed : constructor -> Form error constructor view
succeed constructor =
    Form []
        (\_ -> Request.succeed (Ok ( constructor, [] )))
        (\_ -> Request.succeed (DataSource.succeed []))
        (\_ -> Ok ( constructor, [] ))


runClientValidations : Model -> Form String value view -> Result (List ( String, List String )) ( value, List ( String, List String ) )
runClientValidations model (Form fields decoder serverValidations modelToValue) =
    modelToValue model.fields


type Msg
    = OnFieldInput { name : String, value : String }
    | OnFieldFocus { name : String }
    | OnBlur { name : String }
    | SubmitForm
    | GotFormResponse (Result Http.Error (FieldState String))


type SubmitStatus
    = NotSubmitted
    | Submitting
    | Submitted


type alias Model =
    { fields : FieldState String
    , isSubmitting : SubmitStatus
    , formErrors : Dict String (List String)
    }


type alias ServerUpdate =
    Dict String (RawFieldState String)


type alias FieldState error =
    Dict String (RawFieldState error)


rawValues : Model -> Dict String String
rawValues model =
    model.fields
        |> Dict.map
            (\key value ->
                value.raw |> Maybe.withDefault ""
            )


runValidation : Form error value view -> { name : String, value : String } -> List error
runValidation (Form fields decoder serverValidations modelToValue) newInput =
    let
        matchingDecoder : Maybe (FieldInfoSimple error view)
        matchingDecoder =
            fields
                |> List.Extra.findMap
                    (\( fields_, _ ) ->
                        List.Extra.findMap
                            (\field ->
                                if field.name == newInput.name then
                                    Just field

                                else
                                    Nothing
                            )
                            fields_
                    )
    in
    case matchingDecoder of
        Just decoder_ ->
            case decoder_.clientValidations (Just newInput.value) of
                Ok () ->
                    []

                Err error ->
                    error

        Nothing ->
            []


increaseStatusTo : FieldStatus -> FieldStatus -> FieldStatus
increaseStatusTo increaseTo currentStatus =
    if statusRank increaseTo > statusRank currentStatus then
        increaseTo

    else
        currentStatus


statusRank : FieldStatus -> Int
statusRank status =
    case status of
        NotVisited ->
            0

        Focused ->
            1

        Changed ->
            2

        Blurred ->
            3


isAtLeast : FieldStatus -> FieldStatus -> Bool
isAtLeast atLeastStatus currentStatus =
    statusRank currentStatus >= statusRank atLeastStatus


update : (Msg -> msg) -> (Result Http.Error (FieldState String) -> msg) -> Form String value view -> Msg -> Model -> ( Model, Cmd msg )
update toMsg onResponse ((Form fields decoder serverValidations modelToValue) as form) msg model =
    case msg of
        OnFieldInput { name, value } ->
            let
                initialModel =
                    { model
                        | fields = updatedFields
                        , formErrors = updatedFormErrors
                    }

                updatedFields =
                    model.fields
                        |> Dict.update name
                            (\entry ->
                                case entry of
                                    Just { raw, errors, status } ->
                                        Just
                                            { raw = Just value
                                            , errors = runValidation form { name = name, value = value }
                                            , status = status |> increaseStatusTo Changed
                                            }

                                    Nothing ->
                                        -- TODO calculate errors here? Do server-side errors need to be preserved?
                                        Just
                                            { raw = Just value
                                            , errors = runValidation form { name = name, value = value }
                                            , status = Changed
                                            }
                            )

                updatedFormErrors =
                    case modelToValue updatedFields of
                        Ok ( decodedModel, errors ) ->
                            errors
                                |> Dict.fromList

                        Err errors ->
                            errors
                                |> Dict.fromList
            in
            ( initialModel, Cmd.none )

        OnFieldFocus record ->
            ( { model
                | fields =
                    model.fields
                        |> Dict.update record.name
                            (\maybeExisting ->
                                case maybeExisting of
                                    Just existing ->
                                        Just
                                            { raw = existing.raw
                                            , errors = existing.errors
                                            , status = existing.status |> increaseStatusTo Focused
                                            }

                                    Nothing ->
                                        Nothing
                            )
              }
            , Cmd.none
            )

        OnBlur record ->
            ( { model
                | fields =
                    model.fields
                        |> Dict.update record.name
                            (\maybeExisting ->
                                case maybeExisting of
                                    Just existing ->
                                        Just
                                            { raw = existing.raw
                                            , errors = existing.errors
                                            , status = existing.status |> increaseStatusTo Blurred
                                            }

                                    Nothing ->
                                        Nothing
                            )
              }
            , Cmd.none
            )

        SubmitForm ->
            if hasErrors2 model then
                ( { model | isSubmitting = Submitted }
                , Cmd.none
                )

            else
                ( { model | isSubmitting = Submitting }
                , http "/tailwind-form" form model |> Cmd.map GotFormResponse |> Cmd.map toMsg
                )

        GotFormResponse result ->
            let
                responseTask : Cmd msg
                responseTask =
                    Task.succeed () |> Task.perform (\() -> onResponse result)
            in
            case result of
                Ok fieldData ->
                    ( { model | isSubmitting = Submitted, fields = fieldData }, responseTask )

                Err _ ->
                    -- TODO handle errors - form submission status similar to RemoteData (or with RemoteData type dependency)?
                    ( { model | isSubmitting = Submitted }, responseTask )


initField : RawFieldState error
initField =
    { raw = Nothing
    , errors = []
    , status = NotVisited
    }


init : Form String value view -> Model
init ((Form fields decoder serverValidations modelToValue) as form) =
    let
        initialFields =
            fields
                |> List.concatMap Tuple.first
                |> List.map
                    (\field ->
                        field.initialValue
                            |> Maybe.map
                                (\initial ->
                                    ( field.name
                                    , { raw = Just initial
                                      , errors =
                                            runValidation form
                                                { name = field.name
                                                , value = initial
                                                }
                                      , status = NotVisited
                                      }
                                    )
                                )
                            -- TODO run this part lazily, not eagerly
                            |> Maybe.withDefault
                                ( field.name
                                , { raw = Nothing
                                  , errors = runValidation form { name = field.name, value = "" }
                                  , status = NotVisited
                                  }
                                )
                    )
                |> Dict.fromList
    in
    { fields = initialFields
    , isSubmitting = NotSubmitted
    , formErrors =
        case modelToValue initialFields of
            Ok ( decodedModel, errors ) ->
                errors
                    |> Dict.fromList

            Err errors ->
                errors
                    |> Dict.fromList
    }


toInputRecord :
    FormInfo
    -> String
    -> Maybe String
    -> Maybe (RawFieldState error)
    -> FinalFieldInfo error
    -> FieldRenderInfo error
toInputRecord formInfo name maybeValue info field =
    { toInput =
        ([ Attr.name name |> Just
         , maybeValue
            |> Maybe.withDefault name
            |> Attr.id
            |> Just
         , Html.Events.onFocus (OnFieldFocus { name = name }) |> Just
         , Html.Events.onBlur (OnBlur { name = name }) |> Just
         , case ( maybeValue, info ) of
            ( Just value, _ ) ->
                Attr.value value |> Just

            ( _, Just { raw } ) ->
                valueAttr field raw

            _ ->
                valueAttr field field.initialValue
         , field.type_ |> Attr.type_ |> Just
         , field.required |> Attr.required |> Just
         , if field.type_ == "checkbox" then
            Html.Events.onCheck
                (\checkState ->
                    OnFieldInput
                        { name = name
                        , value =
                            if checkState then
                                "on"

                            else
                                ""
                        }
                )
                |> Just

           else
            Html.Events.onInput
                (\newValue ->
                    OnFieldInput
                        { name = name, value = newValue }
                )
                |> Just
         ]
            |> List.filterMap identity
        )
            ++ toHtmlProperties field.properties
    , toLabel =
        [ maybeValue
            |> Maybe.withDefault name
            |> Attr.for
        ]
    , errors = info |> Maybe.map .errors |> Maybe.withDefault []
    , submitStatus = formInfo.submitStatus
    , status =
        info
            |> Maybe.map .status
            |> Maybe.withDefault NotVisited
    }


toHtmlProperties : List ( String, Encode.Value ) -> List (Html.Attribute msg)
toHtmlProperties properties =
    properties
        |> List.map
            (\( key, value ) ->
                Attr.property key value
            )


toRadioInputRecord :
    FormInfo
    -> String
    -> String
    -> Maybe (RawFieldState error)
    -> FinalFieldInfo error
    -> FieldRenderInfo error
toRadioInputRecord formInfo name itemValue info field =
    { toInput =
        ([ Attr.name name |> Just
         , itemValue
            |> Attr.id
            |> Just
         , Html.Events.onFocus (OnFieldFocus { name = name }) |> Just
         , Html.Events.onBlur (OnBlur { name = name }) |> Just
         , Attr.value itemValue |> Just
         , field.type_ |> Attr.type_ |> Just
         , field.required |> Attr.required |> Just
         , if (info |> Maybe.andThen .raw) == Just itemValue then
            Attr.attribute "checked" "true" |> Just

           else
            Nothing
         , Html.Events.onCheck
            (\checkState ->
                OnFieldInput
                    { name = name
                    , value =
                        if checkState then
                            itemValue

                        else
                            ""
                    }
            )
            |> Just
         ]
            |> List.filterMap identity
        )
            ++ toHtmlProperties field.properties
    , toLabel =
        [ itemValue |> Attr.for
        ]
    , errors = info |> Maybe.map .errors |> Maybe.withDefault []
    , submitStatus = formInfo.submitStatus
    , status =
        info
            |> Maybe.map .status
            |> Maybe.withDefault NotVisited
    }


valueAttr field stringValue =
    if field.type_ == "checkbox" then
        if stringValue == Just "on" then
            Attr.attribute "checked" "true" |> Just

        else
            Nothing

    else
        stringValue |> Maybe.map Attr.value


text :
    String
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            String
            view
            { required : ()
            }
text name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "text"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawValue ->
                Ok ( rawValue |> Maybe.withDefault "", [] )
        , properties = []
        }


hidden :
    String
    -> String
    -> (List (Html.Attribute Msg) -> view)
    -> Field error String view {}
hidden name value toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "hidden"
        , required = False

        -- TODO shouldn't be possible to include any server-side validations on hidden fields
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                -- TODO shouldn't be possible to add any validations or chain anything
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo |> .toInput)
        , decode =
            \rawValue ->
                Ok ( rawValue |> Maybe.withDefault "", [] )
        , properties = []
        }


radio :
    -- TODO inject the error type
    String
    -> ( ( String, item ), List ( String, item ) )
    ->
        (item
         -> FieldRenderInfo error
         -> view
        )
    -> ({ errors : List error, submitStatus : SubmitStatus } -> List view -> view)
    -> Field error (Maybe item) view {}
radio name nonEmptyItemMapping toHtmlFn wrapFn =
    let
        itemMapping : List ( String, item )
        itemMapping =
            nonEmptyItemMapping
                |> List.NonEmpty.toList

        toString : item -> String
        toString targetItem =
            case nonEmptyItemMapping |> List.NonEmpty.toList |> List.filter (\( string, item ) -> item == targetItem) |> List.head of
                Just ( string, _ ) ->
                    string

                Nothing ->
                    "Missing enum"

        fromString : String -> Maybe item
        fromString string =
            itemMapping
                |> Dict.fromList
                |> Dict.get string

        items : List item
        items =
            itemMapping
                |> List.map Tuple.second
    in
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "radio"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            -- TODO use `toString` to set value
            \formInfo _ fieldInfo info ->
                items
                    |> List.map (\item -> toHtmlFn item (toRadioInputRecord formInfo name (toString item) info fieldInfo))
                    |> wrapFn { errors = info |> Maybe.map .errors |> Maybe.withDefault [], submitStatus = formInfo.submitStatus }
        , decode =
            \raw ->
                Ok
                    -- TODO on failure, this should be an error
                    ( raw |> Maybe.andThen fromString
                    , []
                    )
        , properties = []
        }


requiredRadio :
    String
    ->
        { missing : error
        , invalid : String -> error
        }
    -> ( ( String, item ), List ( String, item ) )
    ->
        (item
         -> FieldRenderInfo error
         -> view
        )
    ->
        ({ errors : List error
         , submitStatus : SubmitStatus
         , status : FieldStatus
         }
         -> List view
         -> view
        )
    -> Field error item view {}
requiredRadio name toError nonEmptyItemMapping toHtmlFn wrapFn =
    let
        itemMapping : List ( String, item )
        itemMapping =
            nonEmptyItemMapping
                |> List.NonEmpty.toList

        toString : item -> String
        toString targetItem =
            case nonEmptyItemMapping |> List.NonEmpty.toList |> List.filter (\( string, item ) -> item == targetItem) |> List.head of
                Just ( string, _ ) ->
                    string

                Nothing ->
                    "Missing enum"

        fromString : String -> Maybe item
        fromString string =
            itemMapping
                |> Dict.fromList
                |> Dict.get string

        items : List item
        items =
            itemMapping
                |> List.map Tuple.second
    in
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "radio"
        , required = True
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                items
                    |> List.map (\item -> toHtmlFn item (toRadioInputRecord formInfo name (toString item) info fieldInfo))
                    |> wrapFn { errors = info |> Maybe.map .errors |> Maybe.withDefault [], submitStatus = formInfo.submitStatus, status = info |> Maybe.map .status |> Maybe.withDefault NotVisited }
        , decode =
            \raw ->
                raw
                    |> validateRequiredField toError
                    |> Result.mapError (\_ -> toError.missing)
                    |> Result.andThen
                        (\rawString ->
                            rawString
                                |> fromString
                                |> Result.fromMaybe (toError.invalid rawString)
                        )
                    |> toFieldResult
        , properties = []
        }


toFieldResult : Result error value -> Result (List error) ( value, List error )
toFieldResult result =
    case result of
        Ok okValue ->
            Ok ( okValue, [] )

        Err error ->
            Err [ error ]


submit :
    ({ attrs : List (Html.Attribute Msg)
     , formHasErrors : Bool
     }
     -> view
    )
    -> Field error () view {}
submit toHtmlFn =
    Field
        { name = ""
        , initialValue = Nothing
        , type_ = "submit"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \_ formHasErrors fieldInfo info ->
                let
                    disabledAttrs =
                        if formHasErrors then
                            [ Attr.attribute "disabled" "" ]

                        else
                            []
                in
                toHtmlFn
                    { attrs =
                        [ Attr.type_ "submit"
                        ]

                    --++ disabledAttrs
                    , formHasErrors = formHasErrors
                    }
        , decode =
            \_ ->
                Ok ()
                    |> toFieldResult
        , properties = []
        }


view :
    view
    -> Field error () view constraints
view viewFn =
    Field
        { name = ""
        , initialValue = Nothing
        , type_ = "submit"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \_ _ fieldInfo info ->
                viewFn
        , decode =
            \_ ->
                Ok ()
                    |> toFieldResult
        , properties = []
        }


number :
    String
    ->
        (FieldRenderInfo error
         -> view
        )
    -> Field error (Maybe Int) view { min : Int, max : Int }
number name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "number"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawString ->
                rawString
                    -- TODO handle as error if cannot be parsed
                    |> Maybe.andThen String.toInt
                    |> Ok
                    |> toFieldResult
        , properties = []
        }


requiredNumber :
    String
    -> { missing : error, invalid : String -> error }
    ->
        (FieldRenderInfo error
         -> view
        )
    -> Field error Int view { min : Int, max : Int }
requiredNumber name toError toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "number"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawString ->
                (case rawString of
                    Nothing ->
                        Err toError.missing

                    Just "" ->
                        Err toError.missing

                    Just string ->
                        string
                            |> String.toInt
                            |> Result.fromMaybe (toError.invalid string)
                )
                    |> toFieldResult
        , properties = []
        }


range :
    String
    ->
        { missing : error
        , invalid : String -> error
        }
    ->
        { initial : Int
        , min : Int
        , max : Int
        }
    ->
        (FieldRenderInfo error
         -> view
        )
    -> Field error Int view {}
range name toError options toHtmlFn =
    Field
        { name = name
        , initialValue = Just (String.fromInt options.initial)
        , type_ = "range"
        , required = True
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawString ->
                (case rawString of
                    Nothing ->
                        Err toError.missing

                    Just "" ->
                        Err toError.missing

                    Just string ->
                        string
                            |> String.toInt
                            -- TODO should this be a custom type instead of String error? That way users can customize the error messages
                            |> Result.fromMaybe (toError.invalid string)
                )
                    |> toFieldResult
        , properties =
            []
        }
        |> withStringProperty ( "min", String.fromInt options.min )
        |> withStringProperty ( "max", String.fromInt options.max )


floatRange :
    String
    ->
        { missing : error
        , invalid : String -> error
        }
    ->
        { initial : Float
        , min : Float
        , max : Float
        }
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            Float
            view
            { step : Float
            }
floatRange name toError options toHtmlFn =
    Field
        { name = name
        , initialValue = Just (String.fromFloat options.initial)
        , type_ = "range"
        , required = True
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawString ->
                rawString
                    |> validateRequiredField toError
                    |> Result.andThen
                        (\string ->
                            string
                                |> String.toFloat
                                |> Result.fromMaybe (toError.invalid string)
                        )
                    |> toFieldResult
        , properties = []
        }
        |> withStringProperty ( "min", String.fromFloat options.min )
        |> withStringProperty ( "max", String.fromFloat options.max )


date :
    String
    -> { invalid : String -> error }
    ->
        (FieldRenderInfo error
         -> view
        )
    -> Field error (Maybe Date) view { min : Date, max : Date }
date name toError toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "date"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawString ->
                (if (rawString |> Maybe.withDefault "") == "" then
                    Ok Nothing

                 else
                    rawString
                        |> Maybe.withDefault ""
                        |> Date.fromIsoString
                        |> Result.mapError (\_ -> toError.invalid (rawString |> Maybe.withDefault ""))
                        |> Result.map Just
                )
                    |> toFieldResult
        , properties = []
        }


requiredDate :
    String
    -> { missing : error, invalid : String -> error }
    ->
        (FieldRenderInfo error
         -> view
        )
    -> Field error Date view { min : Date, max : Date }
requiredDate name toError toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "date"
        , required = True
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawString ->
                rawString
                    |> validateRequiredField toError
                    |> Result.andThen
                        (\rawDateString ->
                            Date.fromIsoString rawDateString
                                |> Result.mapError
                                    (\_ -> toError.invalid rawDateString)
                        )
                    |> toFieldResult
        , properties = []
        }


validateRequiredField : { toError | missing : error } -> Maybe String -> Result error String
validateRequiredField toError maybeRaw =
    if (maybeRaw |> Maybe.withDefault "") == "" then
        Err toError.missing

    else
        Ok (maybeRaw |> Maybe.withDefault "")


type alias FieldRenderInfo error =
    { toInput : List (Html.Attribute Msg)
    , toLabel : List (Html.Attribute Msg)
    , errors : List error
    , submitStatus : SubmitStatus
    , status : FieldStatus
    }


checkbox :
    String
    -> Bool
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            Bool
            view
            { required : ()
            }
checkbox name initial toHtmlFn =
    Field
        { name = name
        , initialValue =
            if initial then
                Just "on"

            else
                Nothing
        , type_ = "checkbox"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \formInfo _ fieldInfo info ->
                toHtmlFn (toInputRecord formInfo name Nothing info fieldInfo)
        , decode =
            \rawString ->
                Ok (rawString == Just "on")
                    |> toFieldResult
        , properties = []
        }


withMin : Int -> Field error value view { constraints | min : Int } -> Field error value view constraints
withMin min field =
    withStringProperty ( "min", String.fromInt min ) field


withMax : Int -> Field error value view { constraints | max : Int } -> Field error value view constraints
withMax max field =
    withStringProperty ( "max", String.fromInt max ) field


withStep : Int -> Field error value view { constraints | step : Int } -> Field error value view constraints
withStep max field =
    withStringProperty ( "step", String.fromInt max ) field


withFloatStep : Float -> Field error value view { constraints | step : Float } -> Field error value view constraints
withFloatStep max field =
    withStringProperty ( "step", String.fromFloat max ) field


withMinDate : Date -> Field error value view { constraints | min : Date } -> Field error value view constraints
withMinDate min field =
    withStringProperty ( "min", Date.toIsoString min ) field


withMaxDate : Date -> Field error value view { constraints | max : Date } -> Field error value view constraints
withMaxDate max field =
    withStringProperty ( "max", Date.toIsoString max ) field


type_ : String -> Field error value view constraints -> Field error value view constraints
type_ typeName (Field field) =
    Field
        { field | type_ = typeName }


withInitialValue : String -> Field error value view constraints -> Field error value view constraints
withInitialValue initialValue (Field field) =
    Field { field | initialValue = Just initialValue }


multiple : Field error value view { constraints | multiple : () } -> Field error value view constraints
multiple (Field field) =
    Field { field | properties = ( "multiple", Encode.bool True ) :: field.properties }


withStringProperty : ( String, String ) -> Field error value view constraints1 -> Field error value view constraints2
withStringProperty ( key, value ) (Field field) =
    Field { field | properties = ( key, Encode.string value ) :: field.properties }


withBoolProperty : ( String, Bool ) -> Field error value view constraints1 -> Field error value view constraints2
withBoolProperty ( key, value ) (Field field) =
    Field { field | properties = ( key, Encode.bool value ) :: field.properties }


required : error -> Field error value view { constraints | required : () } -> Field error value view constraints
required missingError (Field field) =
    Field
        { field
            | required = True
            , decode =
                if field.type_ == "checkbox" then
                    \rawValue ->
                        if rawValue == Just "on" then
                            field.decode rawValue

                        else
                            Err [ missingError ]

                else
                    \rawValue ->
                        if rawValue == Nothing || rawValue == Just "" then
                            Err [ missingError ]

                        else
                            field.decode rawValue
        }


telephone : Field error value view constraints -> Field error value view constraints
telephone (Field field) =
    Field { field | type_ = "tel" }


search : Field error value view constraints -> Field error value view constraints
search (Field field) =
    Field { field | type_ = "search" }


password : Field error value view constraints -> Field error value view constraints
password (Field field) =
    Field { field | type_ = "password" }


email : Field error value view constraints -> Field error value view constraints
email (Field field) =
    Field { field | type_ = "email" }


url : Field error value view constraints -> Field error value view constraints
url (Field field) =
    Field { field | type_ = "url" }


withServerValidation : (value -> DataSource (List error)) -> Field error value view constraints -> Field error value view constraints
withServerValidation serverValidation (Field field) =
    Field
        { field
            | serverValidation =
                \value ->
                    case value |> field.decode of
                        Ok ( decoded, [] ) ->
                            serverValidation decoded

                        Ok ( decoded, errors ) ->
                            DataSource.map2 (++)
                                (serverValidation decoded)
                                (DataSource.succeed errors)

                        Err errors ->
                            {- We can't decode the form data, which means there were errors previously in the pipeline
                               we return an empty list, effectively short-circuiting remaining validation and letting
                               the fatal errors propagate through
                            -}
                            DataSource.succeed []
        }


withClientValidation : (value -> Result error mapped) -> Field error value view constraints -> Field error mapped view constraints
withClientValidation mapFn (Field field) =
    Field
        { name = field.name
        , initialValue = field.initialValue
        , type_ = field.type_
        , required = field.required
        , serverValidation = field.serverValidation
        , toHtml = field.toHtml
        , decode =
            \value ->
                value
                    |> field.decode
                    |> Result.andThen
                        (\( okValue, errors ) ->
                            okValue
                                |> mapFn
                                |> Result.mapError List.singleton
                                |> Result.map (\okValue2 -> ( okValue2, errors ))
                        )
        , properties = field.properties
        }


withClientValidation2 : (value -> Result (List error) ( mapped, List error )) -> Field error value view constraints -> Field error mapped view constraints
withClientValidation2 mapFn (Field field) =
    Field
        { name = field.name
        , initialValue = field.initialValue
        , type_ = field.type_
        , required = field.required
        , serverValidation = field.serverValidation
        , toHtml = field.toHtml
        , decode =
            \value ->
                value
                    |> field.decode
                    |> Result.andThen
                        (\( okValue, errors ) ->
                            okValue
                                |> mapFn
                                |> Result.map (\( value_, newErrors ) -> ( value_, newErrors ++ errors ))
                        )
        , properties = field.properties
        }


with : Field error value view constraints -> Form error (value -> form) view -> Form error form view
with (Field field) (Form fields decoder serverValidations modelToValue) =
    let
        thing : (String -> Request (Maybe String)) -> Request (DataSource (List ( String, RawFieldState error )))
        thing optionalFormField_ =
            Request.map2
                (\arg1 arg2 ->
                    arg1
                        |> DataSource.map2 (::)
                            (field.serverValidation arg2
                                |> DataSource.map
                                    (\validationErrors ->
                                        let
                                            clientErrors : List error
                                            clientErrors =
                                                case field.decode arg2 of
                                                    Ok ( value, errors ) ->
                                                        errors

                                                    Err error ->
                                                        error
                                        in
                                        ( field.name
                                        , { errors = validationErrors --++ clientErrors
                                          , raw = arg2
                                          , status = NotVisited -- TODO @@@ is this correct?
                                          }
                                        )
                                    )
                            )
                )
                (serverValidations optionalFormField_)
                (optionalFormField_ field.name)

        withDecoder : (String -> Request (Maybe String)) -> Request (Result (List ( String, List error )) ( form, List ( String, List error ) ))
        withDecoder optionalFormField_ =
            Request.map2
                (combineWithDecoder field.name)
                (optionalFormField_ field.name
                    |> Request.map
                        (\myValue ->
                            myValue
                                |> field.decode
                                |> Result.mapError
                                    (List.map
                                        (\error -> ( field.name, [ error ] ))
                                    )
                                |> Result.map (\( okValue, errors ) -> ( ( okValue, errors ), [] ))
                        )
                )
                (decoder optionalFormField_)
    in
    Form
        (addField field fields)
        withDecoder
        thing
        (\fields_ ->
            let
                maybeValue : Maybe String
                maybeValue =
                    fields_
                        |> Dict.get field.name
                        |> Maybe.andThen .raw
            in
            case modelToValue fields_ of
                Err error ->
                    Err error

                Ok ( okSoFar, formErrors ) ->
                    maybeValue
                        |> field.decode
                        |> Result.mapError
                            (\fieldErrors ->
                                [ ( field.name
                                  , {- these errors are ignored here because we run each field-level validation independently
                                       but we still need to transform the values. We only want to get the form-level validations
                                       from this pipeline.
                                    -}
                                    []
                                  )
                                ]
                            )
                        |> Result.map
                            (\( value, fieldErrors ) ->
                                ( okSoFar value
                                , -- We also ignore the field-level errors here to avoid duplicates.
                                  formErrors
                                )
                            )
        )


combineWithDecoder :
    String
    -> Result (List ( String, List error )) ( ( value, List error ), List ( String, List error ) )
    -> Result (List ( String, List error )) ( value -> form, List ( String, List error ) )
    -> Result (List ( String, List error )) ( form, List ( String, List error ) )
combineWithDecoder fieldName result1 result2 =
    case ( result1, result2 ) of
        ( Ok ( ( value1, errors1 ), errors2 ), Ok ( value2, errors3 ) ) ->
            Ok
                ( value2 value1
                , [ ( fieldName, errors1 ) ]
                    ++ errors2
                    ++ errors3
                )

        ( Err errors1, Err errors2 ) ->
            Err (errors1 ++ errors2)

        ( Err errors1, Ok _ ) ->
            Err errors1

        ( Ok _, Err errors2 ) ->
            Err errors2


map2ResultWithErrors :
    (a -> b -> c)
    -> Result (List ( String, List error )) ( a, List ( String, List error ) )
    -> Result (List ( String, List error )) ( b, List ( String, List error ) )
    -> Result (List ( String, List error )) ( c, List ( String, List error ) )
map2ResultWithErrors mapFn result1 result2 =
    case ( result1, result2 ) of
        ( Ok ( value1, errors1 ), Ok ( value2, errors2 ) ) ->
            Ok
                ( mapFn value1 value2
                , errors1 ++ errors2
                )

        ( Err errors1, Err errors2 ) ->
            Err (errors1 ++ errors2)

        ( Err errors1, Ok _ ) ->
            Err errors1

        ( Ok _, Err errors2 ) ->
            Err errors2


addField : FieldInfo error value view -> List ( List (FieldInfoSimple error view), List view -> List view ) -> List ( List (FieldInfoSimple error view), List view -> List view )
addField field list =
    case list of
        [] ->
            [ ( [ simplify2 field ], identity )
            ]

        ( fields, wrapFn ) :: others ->
            ( simplify2 field :: fields, wrapFn ) :: others


append : Field error value view constraints -> Form error form view -> Form error form view
append (Field field) (Form fields decoder serverValidations modelToValue) =
    Form
        --(field :: fields)
        (addField field fields)
        decoder
        serverValidations
        modelToValue


validate : (form -> List ( String, List error )) -> Form error form view -> Form error form view
validate validateFn (Form fields decoder serverValidations modelToValue) =
    Form fields
        decoder
        serverValidations
        (\model ->
            modelToValue model
                |> Result.andThen
                    (\( decoded, errorsSoFar ) ->
                        let
                            newErrors : List ( String, List error )
                            newErrors =
                                validateFn decoded
                        in
                        if newErrors |> List.isEmpty then
                            Ok ( decoded, errorsSoFar )

                        else
                            -- TODO append instead of replacing
                            Err (errorsSoFar ++ newErrors)
                    )
        )


appendForm : (form1 -> form2 -> form) -> Form error form1 view -> Form error form2 view -> Form error form view
appendForm mapFn (Form fields1 decoder1 serverValidations1 modelToValue1) (Form fields2 decoder2 serverValidations2 modelToValue2) =
    Form
        -- TODO is this ordering correct?
        (fields1 ++ fields2)
        (\optionalFormField_ ->
            Request.map2
                (map2ResultWithErrors mapFn)
                (decoder1 optionalFormField_)
                (decoder2 optionalFormField_)
        )
        (\optionalFormField_ ->
            Request.map2
                (DataSource.map2 (++))
                (serverValidations1 optionalFormField_)
                (serverValidations2 optionalFormField_)
        )
        (\model ->
            map2ResultWithErrors mapFn
                (modelToValue1 model)
                (modelToValue2 model)
        )


wrap : (List view -> view) -> Form error form view -> Form error form view
wrap newWrapFn (Form fields decoder serverValidations modelToValue) =
    Form (wrapFields fields newWrapFn) decoder serverValidations modelToValue


wrapFields :
    List
        ( List (FieldInfoSimple error view)
        , List view -> List view
        )
    -> (List view -> view)
    ->
        List
            ( List (FieldInfoSimple error view)
            , List view -> List view
            )
wrapFields fields newWrapFn =
    case fields of
        [] ->
            [ ( [], newWrapFn >> List.singleton )
            ]

        ( existingFields, wrapFn ) :: others ->
            ( existingFields
            , wrapFn >> newWrapFn >> List.singleton
            )
                :: others


simplify2 : FieldInfo error value view -> FieldInfoSimple error view
simplify2 field =
    { name = field.name
    , initialValue = field.initialValue
    , type_ = field.type_
    , required = field.required
    , serverValidation = field.serverValidation
    , toHtml = field.toHtml
    , properties = field.properties
    , clientValidations =
        \value ->
            value
                |> field.decode
                |> Result.andThen
                    (\( _, errors ) ->
                        if errors |> List.isEmpty then
                            Ok ()

                        else
                            Err errors
                    )
    }


simplify3 : FieldInfoSimple error view -> FinalFieldInfo error
simplify3 field =
    { name = field.name
    , initialValue = field.initialValue
    , type_ = field.type_
    , required = field.required
    , serverValidation = field.serverValidation
    , properties = field.properties
    }



{-
   - If there is at least one file field, then use enctype multi-part. Otherwise use form encoding (or maybe GET with query params?).
   - Should it ever use GET forms?
   - Ability to do server-only validations (like uniqueness check with DataSource)
   - Return error messages that can be presented inline from server response (both on full page load and on client-side request)
   - Add functions for built-in form validations
-}


toHtml :
    { pageReloadSubmit : Bool }
    -> (List (Html.Attribute Msg) -> List view -> view)
    -> Model
    -> Form String value view
    -> view
toHtml { pageReloadSubmit } toForm serverValidationErrors (Form fields decoder serverValidations modelToValue) =
    let
        hasErrors_ : Bool
        hasErrors_ =
            hasErrors2 serverValidationErrors
    in
    toForm
        ([ [ Attr.method "POST" ]
         , if pageReloadSubmit then
            []

           else
            [ Html.Events.onSubmit SubmitForm
            , Attr.novalidate True
            ]
         ]
            |> List.concat
        )
        (fields
            |> List.reverse
            |> List.concatMap
                (\( nestedFields, wrapFn ) ->
                    nestedFields
                        |> List.reverse
                        |> List.map
                            (\field ->
                                let
                                    rawFieldState : RawFieldState String
                                    rawFieldState =
                                        serverValidationErrors.fields
                                            |> Dict.get field.name
                                            |> Maybe.withDefault initField

                                    thing : RawFieldState String
                                    thing =
                                        { rawFieldState
                                            | errors =
                                                rawFieldState.errors
                                                    ++ (serverValidationErrors.formErrors
                                                            |> Dict.get field.name
                                                            |> Maybe.withDefault []
                                                       )
                                        }
                                in
                                field.toHtml { submitStatus = serverValidationErrors.isSubmitting }
                                    hasErrors_
                                    (simplify3 field)
                                    (Just thing)
                            )
                        |> wrapFn
                )
        )


toRequest : Form error value view -> Request (Result (List ( String, List error )) ( value, List ( String, List error ) ))
toRequest (Form fields decoder serverValidations modelToValue) =
    Request.expectFormPost
        (\{ optionalField } ->
            decoder optionalField
        )


apiHandler :
    Form String value view
    -> Request (DataSource (PageServerResponse response))
apiHandler (Form fields decoder serverValidations modelToValue) =
    let
        encodeErrors : List ( String, RawFieldState String ) -> Encode.Value
        encodeErrors errors =
            errors
                |> List.map
                    (\( name, entry ) ->
                        ( name
                        , Encode.object
                            [ ( "errors"
                              , Encode.list Encode.string entry.errors
                              )
                            , ( "raw"
                              , entry.raw |> Maybe.map Encode.string |> Maybe.withDefault Encode.null
                              )
                            ]
                        )
                    )
                |> Encode.object
    in
    Request.map2
        (\decoded errors ->
            errors
                |> DataSource.map
                    (\validationErrors ->
                        if hasErrors validationErrors then
                            Server.Response.json
                                (validationErrors |> encodeErrors)
                                |> PageServerResponse.ServerResponse

                        else
                            Server.Response.json
                                (validationErrors |> encodeErrors)
                                |> PageServerResponse.ServerResponse
                    )
        )
        (Request.expectFormPost
            (\{ optionalField } ->
                decoder optionalField
            )
        )
        (Request.expectFormPost
            (\{ optionalField } ->
                serverValidations optionalField
            )
        )
        |> Request.acceptContentTypes (List.NonEmpty.singleton "application/json")


toRequest2 :
    Form String value view
    ->
        Request
            (DataSource
                (Result Model ( Model, value ))
            )
toRequest2 (Form fields decoder serverValidations modelToValue) =
    Request.map2
        (\decoded errors ->
            errors
                |> DataSource.map
                    (\model ->
                        case decoded of
                            Ok ( value, otherValidationErrors ) ->
                                --if not (hasErrors validationErrors) && (otherValidationErrors |> List.isEmpty) then
                                if otherValidationErrors |> List.isEmpty then
                                    Ok
                                        ( --validationErrors |> Dict.fromList
                                          { model
                                            | fields =
                                                model.fields
                                                    |> combineWithErrors otherValidationErrors
                                          }
                                        , value
                                        )

                                else
                                    --validationErrors
                                    --    |> Dict.fromList
                                    --    |> combineWithErrors otherValidationErrors
                                    { model
                                        | fields =
                                            model.fields
                                                |> combineWithErrors otherValidationErrors
                                    }
                                        |> Err

                            Err otherValidationErrors ->
                                --validationErrors
                                --    |> Dict.fromList
                                --    |> combineWithErrors otherValidationErrors
                                --    |> Err
                                { model
                                    | fields =
                                        model.fields
                                            |> combineWithErrors otherValidationErrors
                                }
                                    |> Err
                    )
        )
        (Request.expectFormPost
            (\{ optionalField } ->
                decoder optionalField
            )
        )
        (Request.expectFormPost
            (\{ optionalField } ->
                serverValidations optionalField
                    |> Request.map
                        (DataSource.map
                            (\thing ->
                                let
                                    fullFieldState : Dict String (RawFieldState String)
                                    fullFieldState =
                                        thing
                                            |> Dict.fromList

                                    otherErrors :
                                        Result
                                            (List ( String, List String ))
                                            ( value, List ( String, List String ) )
                                    otherErrors =
                                        modelToValue fullFieldState
                                in
                                { fields = fullFieldState
                                , isSubmitting = Submitted
                                , formErrors =
                                    case otherErrors of
                                        Ok ( _, okErrors ) ->
                                            okErrors |> Dict.fromList

                                        Err errErrors ->
                                            errErrors |> Dict.fromList
                                }
                            )
                        )
            )
        )


submitHandlers :
    Form String decoded view
    -> (Model -> Result () decoded -> DataSource data)
    ->
        Request
            (DataSource
                (PageServerResponse
                    --{ decoded : Maybe decoded
                    --, errors : Maybe { fields : FieldState, isSubmitting : SubmitStatus }
                    --}
                    data
                )
            )
submitHandlers myForm toDataSource =
    Request.oneOf
        [ apiHandler myForm
        , toRequest2 myForm
            |> Request.map
                (\userOrErrors ->
                    userOrErrors
                        |> DataSource.andThen
                            (\result ->
                                case result of
                                    Ok ( model, decoded ) ->
                                        Ok decoded
                                            |> toDataSource model

                                    Err model ->
                                        Err () |> toDataSource model
                            )
                        |> DataSource.map PageServerResponse.RenderPage
                )
        ]


combineWithErrors : List ( String, List error ) -> Dict String (RawFieldState error) -> Dict String (RawFieldState error)
combineWithErrors validationErrors fieldState =
    validationErrors
        |> List.foldl
            (\( fieldName, fieldErrors ) dict ->
                dict
                    |> Dict.update fieldName
                        (\maybeField ->
                            maybeField
                                |> Maybe.withDefault initField
                                |> (\field -> { field | errors = field.errors ++ fieldErrors })
                                |> Just
                        )
            )
            fieldState


hasErrors : List ( String, RawFieldState error ) -> Bool
hasErrors validationErrors =
    List.any
        (\( _, entry ) ->
            entry.errors |> List.isEmpty |> not
        )
        validationErrors


hasErrors2 : Model -> Bool
hasErrors2 model =
    Dict.Extra.any
        (\_ entry ->
            entry.errors |> List.isEmpty |> not
        )
        model.fields


isSubmitting : Model -> Bool
isSubmitting model =
    model.isSubmitting == Submitting
