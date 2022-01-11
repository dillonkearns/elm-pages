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


http : String -> Form value view -> Model -> Cmd (Result Http.Error FieldState)
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
                            }
                        )
                        (Decode.field "raw" (Decode.nullable Decode.string))
                        (Decode.field "errors" (Decode.list (Codec.decoder errorCodec)))
                    )
                )
        , timeout = Nothing
        , tracker = Nothing
        , url = url_
        }


errorCodec : Codec Error
errorCodec =
    Codec.custom
        (\vCustom vMissing vInvalidDate value ->
            case value of
                Error string ->
                    vCustom string

                MissingRequired ->
                    vMissing

                InvalidDate ->
                    vInvalidDate
        )
        |> Codec.variant1 "Custom" Error Codec.string
        |> Codec.variant0 "MissingRequired" MissingRequired
        |> Codec.variant0 "InvalidDate" InvalidDate
        |> Codec.buildCustom


type Form value view
    = Form
        -- TODO either make this a Dict and include the client-side validations here
        -- OR create a new Dict with ( name => client-side validation ( name -> Result String () )
        (List
            ( List (FieldInfoSimple view)
            , List view -> List view
            )
        )
        (Request (Result Error value))
        (Request
            (DataSource
                (List
                    ( String
                    , { errors : List Error
                      , raw : Maybe String
                      }
                    )
                )
            )
        )
        (Model -> Result (List Error) value)


type Field value view constraints
    = Field (FieldInfo value view)


type alias FormInfo =
    { submitStatus : SubmitStatus
    }


type alias FieldInfoSimple view =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List Error)
    , toHtml :
        FormInfo
        -> Bool
        -> FinalFieldInfo
        -> Maybe { raw : Maybe String, errors : List Error }
        -> view
    , properties : List ( String, Encode.Value )
    , clientValidations : Maybe String -> Result Error ()
    }


type alias FieldInfo value view =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List Error)
    , toHtml :
        FormInfo
        -> Bool
        -> FinalFieldInfo
        -> Maybe { raw : Maybe String, errors : List Error }
        -> view
    , decode : Maybe String -> Result Error value
    , properties : List ( String, Encode.Value )
    }


type alias FinalFieldInfo =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List Error)
    , properties : List ( String, Encode.Value )
    }


succeed : constructor -> Form constructor view
succeed constructor =
    Form []
        (Request.succeed (Ok constructor))
        (Request.succeed (DataSource.succeed []))
        (\_ -> Ok constructor)


runClientValidations : Model -> Form value view -> Result (List Error) value
runClientValidations model (Form fields decoder serverValidations modelToValue) =
    modelToValue model


type Msg
    = OnFieldInput { name : String, value : String }
    | OnFieldFocus { name : String }
    | OnBlur
    | SubmitForm
    | GotFormResponse (Result Http.Error FieldState)


type SubmitStatus
    = NotSubmitted
    | Submitting
    | Submitted


type alias Model =
    { fields : FieldState
    , isSubmitting : SubmitStatus
    }


type alias FieldState =
    Dict String { raw : Maybe String, errors : List Error }


rawValues : Model -> Dict String String
rawValues model =
    model.fields
        |> Dict.map
            (\key value ->
                value.raw |> Maybe.withDefault ""
            )


runValidation : Form value view -> { name : String, value : String } -> List Error
runValidation (Form fields decoder serverValidations modelToValue) newInput =
    let
        matchingDecoder : Maybe (FieldInfoSimple view)
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
                    [ error ]

        Nothing ->
            []


update : (Msg -> msg) -> (Result Http.Error FieldState -> msg) -> Form value view -> Msg -> Model -> ( Model, Cmd msg )
update toMsg onResponse form msg model =
    case msg of
        OnFieldInput { name, value } ->
            -- TODO run client-side validations
            ( { model
                | fields =
                    model.fields
                        |> Dict.update name
                            (\entry ->
                                case entry of
                                    Just { raw, errors } ->
                                        -- TODO calculate errors here?
                                        Just { raw = Just value, errors = runValidation form { name = name, value = value } }

                                    Nothing ->
                                        -- TODO calculate errors here?
                                        Just { raw = Just value, errors = [] }
                            )
              }
            , Cmd.none
            )

        OnFieldFocus record ->
            ( model, Cmd.none )

        OnBlur ->
            ( model, Cmd.none )

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
                    -- TODO handle errors
                    ( { model | isSubmitting = Submitted }, responseTask )


init : Form value view -> Model
init ((Form fields decoder serverValidations modelToValue) as form) =
    { fields =
        fields
            |> List.concatMap Tuple.first
            |> List.map
                (\field ->
                    field.initialValue
                        |> Maybe.map
                            (\initial ->
                                ( field.name
                                , { raw = Just initial
                                  , errors = runValidation form { name = field.name, value = initial }
                                  }
                                )
                            )
                        |> Maybe.withDefault ( field.name, { raw = Nothing, errors = runValidation form { name = field.name, value = "" } } )
                )
            |> Dict.fromList
    , isSubmitting = NotSubmitted
    }


toInputRecord :
    FormInfo
    -> String
    -> Maybe String
    -> Maybe { raw : Maybe String, errors : List Error }
    -> FinalFieldInfo
    -> FieldRenderInfo
toInputRecord formInfo name maybeValue info field =
    { toInput =
        ([ Attr.name name |> Just
         , maybeValue
            |> Maybe.withDefault name
            |> Attr.id
            |> Just
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
    -> Maybe { raw : Maybe String, errors : List Error }
    -> FinalFieldInfo
    -> FieldRenderInfo
toRadioInputRecord formInfo name itemValue info field =
    { toInput =
        ([ Attr.name name |> Just
         , itemValue
            |> Attr.id
            |> Just
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
        (FieldRenderInfo
         -> view
        )
    -> Field String view {}
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

        -- TODO should it be Err if Nothing?
        , decode = Maybe.withDefault "" >> Ok
        , properties = []
        }


hidden :
    String
    -> String
    -> (List (Html.Attribute Msg) -> view)
    -> Field String view {}
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

        -- TODO should it be Err if Nothing?
        , decode = Maybe.withDefault "" >> Ok
        , properties = []
        }


radio :
    String
    -> ( ( String, item ), List ( String, item ) )
    ->
        (item
         -> FieldRenderInfo
         -> view
        )
    -> ({ errors : List Error, submitStatus : SubmitStatus } -> List view -> view)
    -> Field (Maybe item) view {}
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
                raw
                    |> Maybe.andThen fromString
                    |> Ok
        , properties = []
        }


requiredRadio :
    String
    -> ( ( String, item ), List ( String, item ) )
    ->
        (item
         -> FieldRenderInfo
         -> view
        )
    -> ({ errors : List Error, submitStatus : SubmitStatus } -> List view -> view)
    -> Field item view {}
requiredRadio name nonEmptyItemMapping toHtmlFn wrapFn =
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
                    |> wrapFn { errors = info |> Maybe.map .errors |> Maybe.withDefault [], submitStatus = formInfo.submitStatus }
        , decode =
            \raw ->
                raw
                    |> validateRequiredField
                    |> Result.andThen (fromString >> Result.fromMaybe (Error "Invalid radio option"))
        , properties = []
        }


submit :
    ({ attrs : List (Html.Attribute Msg)
     , formHasErrors : Bool
     }
     -> view
    )
    -> Field () view {}
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
        , decode = \_ -> Ok ()
        , properties = []
        }


view :
    view
    -> Field () view constraints
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
        , decode = \_ -> Ok ()
        , properties = []
        }


number :
    String
    ->
        (FieldRenderInfo
         -> view
        )
    -> Field (Maybe Int) view { min : Int, max : Int }
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
                    |> Maybe.andThen String.toInt
                    |> Ok
        , properties = []
        }


type Error
    = Error String
    | MissingRequired
    | InvalidDate


requiredNumber :
    String
    ->
        (FieldRenderInfo
         -> view
        )
    -> Field Int view { min : Int, max : Int }
requiredNumber name toHtmlFn =
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
                case rawString of
                    Nothing ->
                        Err MissingRequired

                    Just string ->
                        -- TODO should be a required field missing error if this is empty string
                        string
                            |> String.toInt
                            -- TODO should this be a custom type instead of String error? That way users can customize the error messages
                            |> Result.fromMaybe (Error "Not a valid number")
        , properties = []
        }


range :
    String
    ->
        { initial : Int
        , min : Int
        , max : Int
        }
    ->
        (FieldRenderInfo
         -> view
        )
    -> Field Int view {}
range name options toHtmlFn =
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
                case rawString of
                    Nothing ->
                        Err MissingRequired

                    Just string ->
                        -- TODO should be a required field missing error if this is empty string
                        string
                            |> String.toInt
                            -- TODO should this be a custom type instead of String error? That way users can customize the error messages
                            |> Result.fromMaybe (Error "Not a valid number")
        , properties =
            []
        }
        |> withStringProperty ( "min", String.fromInt options.min )
        |> withStringProperty ( "max", String.fromInt options.max )


floatRange :
    String
    ->
        { initial : Float
        , min : Float
        , max : Float
        }
    ->
        (FieldRenderInfo
         -> view
        )
    ->
        Field
            Float
            view
            { step : Float
            }
floatRange name options toHtmlFn =
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
                    |> validateRequiredField
                    |> Result.andThen
                        -- TODO should this be a custom type instead of String error? That way users can customize the error messages
                        (String.toFloat >> Result.fromMaybe (Error "Not a valid number"))
        , properties = []
        }
        |> withStringProperty ( "min", String.fromFloat options.min )
        |> withStringProperty ( "max", String.fromFloat options.max )


date :
    String
    ->
        (FieldRenderInfo
         -> view
        )
    -> Field (Maybe Date) view { min : Date, max : Date }
date name toHtmlFn =
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
                if (rawString |> Maybe.withDefault "") == "" then
                    Ok Nothing

                else
                    rawString
                        |> Maybe.withDefault ""
                        |> Date.fromIsoString
                        |> Result.mapError (\_ -> InvalidDate)
                        |> Result.map Just
        , properties = []
        }


requiredDate :
    String
    ->
        (FieldRenderInfo
         -> view
        )
    -> Field Date view { min : Date, max : Date }
requiredDate name toHtmlFn =
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
                    |> validateRequiredField
                    |> Result.andThen
                        (\rawDateString ->
                            Date.fromIsoString rawDateString
                                |> Result.mapError (\_ -> InvalidDate)
                        )
        , properties = []
        }


validateRequiredField : Maybe String -> Result Error String
validateRequiredField maybeRaw =
    if (maybeRaw |> Maybe.withDefault "") == "" then
        Err MissingRequired

    else
        Ok (maybeRaw |> Maybe.withDefault "")


type alias FieldRenderInfo =
    { toInput : List (Html.Attribute Msg)
    , toLabel : List (Html.Attribute Msg)
    , errors : List Error
    , submitStatus : SubmitStatus
    }


checkbox :
    String
    -> Bool
    ->
        (FieldRenderInfo
         -> view
        )
    -- TODO should be Date type
    -> Field Bool view {}
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
        , properties = []
        }


withMin : Int -> Field value view { constraints | min : Int } -> Field value view constraints
withMin min field =
    withStringProperty ( "min", String.fromInt min ) field


withMax : Int -> Field value view { constraints | max : Int } -> Field value view constraints
withMax max field =
    withStringProperty ( "max", String.fromInt max ) field


withStep : Int -> Field value view { constraints | step : Int } -> Field value view constraints
withStep max field =
    withStringProperty ( "step", String.fromInt max ) field


withFloatStep : Float -> Field value view { constraints | step : Float } -> Field value view constraints
withFloatStep max field =
    withStringProperty ( "step", String.fromFloat max ) field


withMinDate : Date -> Field value view { constraints | min : Date } -> Field value view constraints
withMinDate min field =
    withStringProperty ( "min", Date.toIsoString min ) field


withMaxDate : Date -> Field value view { constraints | max : Date } -> Field value view constraints
withMaxDate max field =
    withStringProperty ( "max", Date.toIsoString max ) field


type_ : String -> Field value view constraints -> Field value view constraints
type_ typeName (Field field) =
    Field
        { field | type_ = typeName }


withInitialValue : String -> Field value view constraints -> Field value view constraints
withInitialValue initialValue (Field field) =
    Field { field | initialValue = Just initialValue }


multiple : Field value view { constraints | multiple : () } -> Field value view constraints
multiple (Field field) =
    Field { field | properties = ( "multiple", Encode.bool True ) :: field.properties }


withStringProperty : ( String, String ) -> Field value view constraints1 -> Field value view constraints2
withStringProperty ( key, value ) (Field field) =
    Field { field | properties = ( key, Encode.string value ) :: field.properties }


withBoolProperty : ( String, Bool ) -> Field value view constraints1 -> Field value view constraints2
withBoolProperty ( key, value ) (Field field) =
    Field { field | properties = ( key, Encode.bool value ) :: field.properties }


required : Field value view constraints -> Field value view constraints
required (Field field) =
    Field { field | required = True }


telephone : Field value view constraints -> Field value view constraints
telephone (Field field) =
    Field { field | type_ = "tel" }


search : Field value view constraints -> Field value view constraints
search (Field field) =
    Field { field | type_ = "search" }


password : Field value view constraints -> Field value view constraints
password (Field field) =
    Field { field | type_ = "password" }


email : Field value view constraints -> Field value view constraints
email (Field field) =
    Field { field | type_ = "email" }


url : Field value view constraints -> Field value view constraints
url (Field field) =
    Field { field | type_ = "url" }


withServerValidation : (value -> DataSource (List String)) -> Field value view constraints -> Field value view constraints
withServerValidation serverValidation (Field field) =
    Field
        { field
            | serverValidation =
                \value ->
                    case value |> field.decode of
                        Ok decoded ->
                            serverValidation decoded
                                |> DataSource.map (List.map Error)

                        Err error ->
                            DataSource.fail <| "Could not decode form data: " ++ errorToString error
        }


errorToString : Error -> String
errorToString error =
    case error of
        MissingRequired ->
            "This field is required"

        Error errorString ->
            errorString

        InvalidDate ->
            "Invalid date"


withClientValidation : (value -> Result String mapped) -> Field value view constraints -> Field mapped view constraints
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
                    |> Result.andThen (mapFn >> Result.mapError Error)
        , properties = field.properties
        }


with : Field value view constraints -> Form (value -> form) view -> Form form view
with (Field field) (Form fields decoder serverValidations modelToValue) =
    let
        thing : Request (DataSource (List ( String, { raw : Maybe String, errors : List Error } )))
        thing =
            Request.map2
                (\arg1 arg2 ->
                    arg1
                        |> DataSource.map2 (::)
                            (field.serverValidation arg2
                                |> DataSource.map
                                    (\validationErrors ->
                                        let
                                            clientErrors : List Error
                                            clientErrors =
                                                case field.decode arg2 of
                                                    Ok _ ->
                                                        []

                                                    Err error ->
                                                        [ error ]
                                        in
                                        ( field.name
                                        , { errors = validationErrors ++ clientErrors
                                          , raw = arg2
                                          }
                                        )
                                    )
                            )
                )
                serverValidations
                (Request.optionalFormField_ field.name)
    in
    Form
        (addField field fields)
        (Request.map2
            (Result.map2 (|>))
            (Request.optionalFormField_ field.name |> Request.map field.decode)
            decoder
        )
        thing
        (\model ->
            let
                maybeValue : Maybe String
                maybeValue =
                    model.fields
                        |> Dict.get field.name
                        |> Maybe.andThen .raw
            in
            case modelToValue model of
                Err error ->
                    Err error

                Ok okSoFar ->
                    maybeValue
                        |> field.decode
                        -- TODO have a `List String` for field validation errors, too
                        |> Result.mapError List.singleton
                        |> Result.andThen (okSoFar >> Ok)
        )


addField : FieldInfo value view -> List ( List (FieldInfoSimple view), List view -> List view ) -> List ( List (FieldInfoSimple view), List view -> List view )
addField field list =
    case list of
        [] ->
            [ ( [ simplify2 field ], identity )
            ]

        ( fields, wrapFn ) :: others ->
            ( simplify2 field :: fields, wrapFn ) :: others


append : Field value view constraints -> Form form view -> Form form view
append (Field field) (Form fields decoder serverValidations modelToValue) =
    Form
        --(field :: fields)
        (addField field fields)
        decoder
        serverValidations
        modelToValue


appendForm : (form1 -> form2 -> form) -> Form form1 view -> Form form2 view -> Form form view
appendForm mapFn (Form fields1 decoder1 serverValidations1 modelToValue1) (Form fields2 decoder2 serverValidations2 modelToValue2) =
    Form
        -- TODO is this ordering correct?
        (fields1 ++ fields2)
        (Request.map2 (Result.map2 mapFn) decoder1 decoder2)
        (Request.map2
            (DataSource.map2 (++))
            serverValidations1
            serverValidations2
        )
        (\model ->
            Result.map2 mapFn
                (modelToValue1 model)
                (modelToValue2 model)
        )


wrap : (List view -> view) -> Form form view -> Form form view
wrap newWrapFn (Form fields decoder serverValidations modelToValue) =
    Form (wrapFields fields newWrapFn) decoder serverValidations modelToValue


wrapFields :
    List
        ( List (FieldInfoSimple view)
        , List view -> List view
        )
    -> (List view -> view)
    ->
        List
            ( List (FieldInfoSimple view)
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


simplify2 : FieldInfo value view -> FieldInfoSimple view
simplify2 field =
    { name = field.name
    , initialValue = field.initialValue
    , type_ = field.type_
    , required = field.required
    , serverValidation = field.serverValidation
    , toHtml = field.toHtml
    , properties = field.properties
    , clientValidations = \value -> value |> field.decode |> Result.map (\_ -> ())
    }


simplify3 : FieldInfoSimple view -> FinalFieldInfo
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
    -> Form value view
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
                                field.toHtml { submitStatus = serverValidationErrors.isSubmitting }
                                    hasErrors_
                                    (simplify3 field)
                                    (serverValidationErrors.fields
                                        |> Dict.get field.name
                                    )
                            )
                        |> wrapFn
                )
        )


toRequest : Form value view -> Request (Result Error value)
toRequest (Form fields decoder serverValidations modelToValue) =
    Request.expectFormPost
        (\_ ->
            decoder
        )


apiHandler :
    Form value view
    -> Request (DataSource (PageServerResponse response))
apiHandler (Form fields decoder serverValidations modelToValue) =
    let
        encodeErrors : List ( String, { a | errors : List Error, raw : Maybe String } ) -> Encode.Value
        encodeErrors errors =
            errors
                |> List.map
                    (\( name, entry ) ->
                        ( name
                        , Encode.object
                            [ ( "errors"
                              , Encode.list (errorCodec |> Codec.encoder) entry.errors
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
            (\_ ->
                decoder
            )
        )
        (Request.expectFormPost
            (\_ ->
                serverValidations
            )
        )
        |> Request.acceptContentTypes (List.NonEmpty.singleton "application/json")


toRequest2 :
    Form value view
    ->
        Request
            (DataSource
                (Result FieldState ( Result Error value, FieldState ))
            )
toRequest2 (Form fields decoder serverValidations modelToValue) =
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
                            Ok
                                ( decoded
                                , validationErrors
                                    |> Dict.fromList
                                )
                    )
        )
        (Request.expectFormPost
            (\_ ->
                decoder
            )
        )
        (Request.expectFormPost
            (\_ ->
                Request.oneOf
                    [ serverValidations
                        |> Request.acceptContentTypes (List.NonEmpty.singleton "application/json")
                    , serverValidations
                    ]
            )
        )


hasErrors : List ( String, { errors : List Error, raw : Maybe String } ) -> Bool
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
