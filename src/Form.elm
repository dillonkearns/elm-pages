module Form exposing
    ( Model, Msg(..), init, update, submitHandlers, toHtml, ServerUpdate
    , Form(..), succeed
    , wrap, wrapFields
    , isSubmitting, SubmitStatus(..)
    , FieldRenderInfo, FieldStatus(..), isAtLeast
    , with, append, appendForm
    , Field
    , withInitialValue
    , checkbox, date, time, email, hidden, multiple, int, float, password, radio, range, telephone, text, url, floatRange, search
    , submit
    , required
    , validate
    , withServerValidation
    , withMax, withMin
    , withStep
    , submitHandlers2, toHtml2
    , hasErrors2, rawValues, runClientValidations, withClientValidation, withClientValidation2
    , FieldInfoSimple, FieldState, FinalFieldInfo, FormInfo, No, RawFieldState, TimeOfDay, Yes
    )

{-|


## Wiring

@docs Model, Msg, init, update, submitHandlers, toHtml, ServerUpdate


## Defining a Form

@docs Form, succeed


## Building Up the Form View Layout

@docs wrap, wrapFields


## Form Submit Status

The form submissions are handled internally. Both tracking the submit status, and performing the underlying HTTP request.

@docs isSubmitting, SubmitStatus


## Rendering a Field

@docs FieldRenderInfo, FieldStatus, isAtLeast


## Appending to forms

@docs with, append, appendForm


## Fields

@docs Field


## Initial Values

@docs withInitialValue


## Field Types

@docs checkbox, date, time, email, hidden, multiple, int, float, password, radio, range, telephone, text, url, floatRange, search


## Input Fields


### Submit Buttons

@docs submit


## Built-In Browser Validations

Whenever possible, it's best to use the platform. For example, if you mark a field as number, the UI will give you number inputs. If you use an email input field, a mobile phone can display a special email input keyboard, or a desktop browser can suggest autofill input based on that.

A Date type can be entered with the native date picker UI of the user's browser, which can be mobile-friendly by using the native mobile browser's built-in UI. But this also implies a validation, and can't be parsed into an Elm type. So you get two for the price of one. A UI, and a valdation. The validations are run on both client and server, so you can trust them without having to maintain duplicate logic for the server-side.


### Required

@docs required


### Custom Client-Side Validations

@docs validate


### Server-Side Validations

@docs withServerValidation


### Minimum and Maximum Values

@docs withMax, withMin

Steps

@docs withStep


## Forms


## Validations


## Not Named Properly Yet

@docs submitHandlers2, toHtml2


## Internals?

@docs hasErrors2, rawValues, runClientValidations, withClientValidation, withClientValidation2

-}

import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict exposing (Dict)
import Dict.Extra
import Form.Value
import FormDecoder
import Html
import Html.Attributes as Attr
import Html.Events
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import List.Extra
import List.NonEmpty
import PageServerResponse exposing (PageServerResponse)
import Server.Request as Request exposing (Request)
import Server.Response
import Task
import Url


{-| -}
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
                        (Decode.field "errors" (Decode.list Decode.string))
                    )
                )
        , timeout = Nothing
        , tracker = Nothing
        , url = url_
        }


{-| -}
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


{-| -}
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


{-| -}
succeed : constructor -> Form error constructor view
succeed constructor =
    Form []
        (\_ -> Request.succeed (Ok ( constructor, [] )))
        (\_ -> Request.succeed (DataSource.succeed []))
        (\_ -> Ok ( constructor, [] ))


{-| -}
runClientValidations : Model -> Form String value view -> Result (List ( String, List String )) ( value, List ( String, List String ) )
runClientValidations model (Form fields decoder serverValidations modelToValue) =
    modelToValue model.fields


{-| -}
type Msg
    = OnFieldInput { name : String, value : String }
    | OnFieldFocus { name : String }
    | OnBlur { name : String }
    | SubmitForm
    | GotFormResponse (Result Http.Error (FieldState String))


{-| -}
type SubmitStatus
    = NotSubmitted
    | Submitting
    | Submitted


{-| -}
type alias Model =
    { fields : FieldState String
    , isSubmitting : SubmitStatus
    , formErrors : Dict String (List String)
    }


{-| -}
type alias ServerUpdate =
    Dict String (RawFieldState String)


type alias FieldState error =
    Dict String (RawFieldState error)


{-| -}
rawValues : Model -> Dict String String
rawValues model =
    model.fields
        |> Dict.map
            (\_ value ->
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


{-| -}
isAtLeast : FieldStatus -> FieldStatus -> Bool
isAtLeast atLeastStatus currentStatus =
    statusRank currentStatus >= statusRank atLeastStatus


{-| -}
update : (Msg -> msg) -> (Result Http.Error (FieldState String) -> msg) -> Form String value view -> Msg -> Model -> ( Model, Cmd msg )
update toMsg onResponse ((Form fields decoder serverValidations modelToValue) as form) msg model =
    case msg of
        OnFieldInput { name, value } ->
            let
                initialModel : Model
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
                                    Just { status } ->
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
                        Ok ( _, errors ) ->
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


{-| -}
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
            Ok ( _, errors ) ->
                errors
                    |> Dict.fromList

            Err errors ->
                errors
                    |> Dict.fromList
    }


nonEmptyString : String -> Maybe String
nonEmptyString string =
    if string == "" then
        Nothing

    else
        Just string


toInputRecord :
    FormInfo
    -> String
    -> Maybe String
    -> Maybe (RawFieldState error)
    -> FinalFieldInfo error
    -> FieldRenderInfo error
toInputRecord formInfo name maybeValue info field =
    { toInput =
        ([ name |> nonEmptyString |> Maybe.map Attr.name
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
        ([ name |> nonEmptyString |> Maybe.map Attr.name
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


{-| -}
text :
    String
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            (Maybe String)
            view
            { required : ()
            , plainText : ()
            , wasMapped : No
            , initial : String
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
                Ok
                    ( if rawValue == Just "" then
                        Nothing

                      else
                        rawValue
                    , []
                    )
        , properties = []
        }


{-| -}
hidden :
    String
    -> String
    -> (List (Html.Attribute Msg) -> view)
    ->
        Field
            error
            String
            view
            { initial : String
            }
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


{-| -}
radio :
    -- TODO inject the error type
    String
    -> error
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
    ->
        Field
            error
            (Maybe item)
            view
            { required : ()
            , wasMapped : No
            }
radio name invalidError nonEmptyItemMapping toHtmlFn wrapFn =
    let
        itemMapping : List ( String, item )
        itemMapping =
            nonEmptyItemMapping
                |> List.NonEmpty.toList

        toString : item -> String
        toString targetItem =
            case nonEmptyItemMapping |> List.NonEmpty.toList |> List.filter (\( _, item ) -> item == targetItem) |> List.head of
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
            \formInfo _ fieldInfo info ->
                items
                    |> List.map (\item -> toHtmlFn item (toRadioInputRecord formInfo name (toString item) info fieldInfo))
                    |> wrapFn { errors = info |> Maybe.map .errors |> Maybe.withDefault [], submitStatus = formInfo.submitStatus, status = info |> Maybe.map .status |> Maybe.withDefault NotVisited }
        , decode =
            \raw ->
                (if raw == Just "" then
                    Nothing

                 else
                    raw
                )
                    |> Maybe.map
                        (\justValue ->
                            justValue
                                |> fromString
                                |> Result.fromMaybe invalidError
                                |> Result.map (\decoded -> ( Just decoded, [] ))
                                |> Result.mapError List.singleton
                        )
                    |> Maybe.withDefault (Ok ( Nothing, [] ))
        , properties = []
        }


toFieldResult : Result error value -> Result (List error) ( value, List error )
toFieldResult result =
    case result of
        Ok okValue ->
            Ok ( okValue, [] )

        Err error ->
            Err [ error ]


{-| -}
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
            \_ formHasErrors _ _ ->
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


{-| -}
int :
    String
    -> { invalid : String -> error }
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            (Maybe Int)
            view
            { min : Int
            , max : Int
            , required : ()
            , wasMapped : No
            , initial : Int
            }
int name toError toHtmlFn =
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
                        Ok Nothing

                    Just "" ->
                        Ok Nothing

                    Just string ->
                        string
                            |> String.toInt
                            |> Result.fromMaybe (toError.invalid string)
                            |> Result.map Just
                )
                    |> toFieldResult
        , properties = []
        }


{-| -}
float :
    String
    -> { invalid : String -> error }
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            (Maybe Float)
            view
            { min : Float
            , max : Float
            , required : ()
            , wasMapped : No
            , initial : Float
            }
float name toError toHtmlFn =
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
                        Ok Nothing

                    Just "" ->
                        Ok Nothing

                    Just string ->
                        string
                            |> String.toFloat
                            |> Result.fromMaybe (toError.invalid string)
                            |> Result.map Just
                )
                    |> toFieldResult
        , properties = []
        }


{-| -}
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
                (rawString
                    |> validateRequiredField toError
                    |> Result.andThen
                        (\string ->
                            string
                                |> String.toInt
                                |> Result.fromMaybe (toError.invalid string)
                        )
                    |> Result.andThen
                        (\decodedInt ->
                            if decodedInt > options.max || decodedInt < options.min then
                                Err (toError.invalid (decodedInt |> String.fromInt))

                            else
                                Ok decodedInt
                        )
                )
                    |> toFieldResult
        , properties =
            []
        }
        |> withStringProperty ( "min", String.fromInt options.min )
        |> withStringProperty ( "max", String.fromInt options.max )


{-| -}
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
                (rawString
                    |> validateRequiredField toError
                    |> Result.andThen
                        (\string ->
                            string
                                |> String.toFloat
                                |> Result.fromMaybe (toError.invalid string)
                        )
                    |> Result.andThen
                        (\decodedFloat ->
                            if decodedFloat > options.max || decodedFloat < options.min then
                                Err (toError.invalid (decodedFloat |> String.fromFloat))

                            else
                                Ok decodedFloat
                        )
                )
                    |> toFieldResult
        , properties = []
        }
        |> withStringProperty ( "min", String.fromFloat options.min )
        |> withStringProperty ( "max", String.fromFloat options.max )


{-| -}
date :
    String
    -> { invalid : String -> error }
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            (Maybe Date)
            view
            { min : Date
            , max : Date
            , required : ()
            , wasMapped : No
            , initial : Date
            }
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


type alias TimeOfDay =
    { hours : Int, minutes : Int }


{-| -}
time :
    String
    -> { invalid : String -> error }
    ->
        (FieldRenderInfo error
         -> view
        )
    ->
        Field
            error
            (Maybe TimeOfDay)
            view
            { -- TODO support min/max
              --min : ???,
              --, max : ???,
              required : ()
            , wasMapped : No
            }
time name toError toHtmlFn =
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
                        |> parseTimeOfDay
                        |> Result.mapError (\_ -> toError.invalid (rawString |> Maybe.withDefault ""))
                        |> Result.map Just
                )
                    |> toFieldResult
        , properties = []
        }


parseTimeOfDay rawTimeOfDay =
    case rawTimeOfDay |> String.split ":" |> List.map String.toInt of
        [ Just hours, Just minutes ] ->
            Ok
                { hours = hours
                , minutes = minutes
                }

        _ ->
            Err ()


validateRequiredField : { toError | missing : error } -> Maybe String -> Result error String
validateRequiredField toError maybeRaw =
    if (maybeRaw |> Maybe.withDefault "") == "" then
        Err toError.missing

    else
        Ok (maybeRaw |> Maybe.withDefault "")


{-| -}
type alias FieldRenderInfo error =
    { toInput : List (Html.Attribute Msg)
    , toLabel : List (Html.Attribute Msg)
    , errors : List error
    , submitStatus : SubmitStatus
    , status : FieldStatus
    }


{-| -}
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


{-| -}
withMin : Form.Value.Value valueType -> Field error value view { constraints | min : valueType } -> Field error value view constraints
withMin min field =
    withStringProperty ( "min", Form.Value.toString min ) field


{-| -}
withMax : Form.Value.Value valueType -> Field error value view { constraints | max : valueType } -> Field error value view constraints
withMax max field =
    withStringProperty ( "max", Form.Value.toString max ) field


{-| -}
withStep : Form.Value.Value valueType -> Field error value view { constraints | step : valueType } -> Field error value view constraints
withStep max field =
    withStringProperty ( "step", Form.Value.toString max ) field


{-| -}
withInitialValue : Form.Value.Value valueType -> Field error value view { constraints | initial : valueType } -> Field error value view constraints
withInitialValue initialValue (Field field) =
    Field { field | initialValue = Just (Form.Value.toString initialValue) }


{-| -}
multiple : Field error value view { constraints | multiple : () } -> Field error value view constraints
multiple (Field field) =
    Field { field | properties = ( "multiple", Encode.bool True ) :: field.properties }


withStringProperty : ( String, String ) -> Field error value view constraints1 -> Field error value view constraints2
withStringProperty ( key, value ) (Field field) =
    Field { field | properties = ( key, Encode.string value ) :: field.properties }


type Yes
    = Yes


type No
    = No


{-| -}
required :
    error
    ->
        Field
            error
            (Maybe value)
            view
            { constraints
                | required : ()
                , wasMapped : No
            }
    -> Field error value view { constraints | wasMapped : No }
required missingError (Field field) =
    Field
        { name = field.name
        , initialValue = field.initialValue
        , type_ = field.type_
        , required = True
        , serverValidation = field.serverValidation
        , toHtml = field.toHtml
        , decode =
            \rawValue ->
                case field.decode rawValue of
                    Ok ( Just decoded, errors ) ->
                        Ok ( decoded, errors )

                    Ok ( Nothing, _ ) ->
                        Err [ missingError ]

                    Err errors ->
                        Err errors
        , properties = field.properties
        }


{-| -}
telephone : Field error value view { constraints | plainText : () } -> Field error value view constraints
telephone (Field field) =
    Field { field | type_ = "tel" }


{-| -}
search : Field error value view { constraints | plainText : () } -> Field error value view constraints
search (Field field) =
    Field { field | type_ = "search" }


{-| -}
password : Field error value view { constraints | plainText : () } -> Field error value view constraints
password (Field field) =
    Field { field | type_ = "password" }


{-| -}
email : Field error value view { constraints | plainText : () } -> Field error value view constraints
email (Field field) =
    Field { field | type_ = "email" }


{-| -}
url : Field error value view { constraints | plainText : () } -> Field error value view constraints
url (Field field) =
    Field { field | type_ = "url" }


{-| -}
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

                        Err _ ->
                            {- We can't decode the form data, which means there were errors previously in the pipeline
                               we return an empty list, effectively short-circuiting remaining validation and letting
                               the fatal errors propagate through
                            -}
                            DataSource.succeed []
        }


{-| -}
withClientValidation : (value -> Result error mapped) -> Field error value view constraints -> Field error mapped view { constraints | wasMapped : Yes }
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


{-| -}
withClientValidation2 : (value -> Result (List error) ( mapped, List error )) -> Field error value view constraints -> Field error mapped view { constraints | wasMapped : Yes }
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


{-| -}
with : Field error value view constraints -> Form error (value -> form) view -> Form error form view
with (Field field) (Form fields decoder serverValidations modelToValue) =
    let
        thing : (String -> Request (Maybe String)) -> Request (DataSource (List ( String, RawFieldState error )))
        thing expectFormField =
            Request.map2
                (\arg1 arg2 ->
                    arg1
                        |> DataSource.map2 (::)
                            (field.serverValidation arg2
                                |> DataSource.map
                                    (\validationErrors ->
                                        ( field.name
                                        , { errors = validationErrors --++ clientErrors
                                          , raw = arg2
                                          , status = NotVisited -- TODO @@@ is this correct?
                                          }
                                        )
                                    )
                            )
                )
                (serverValidations expectFormField)
                (field.name
                    |> nonEmptyString
                    |> Maybe.map expectFormField
                    |> Maybe.withDefault (Request.succeed Nothing)
                )

        withDecoder : (String -> Request (Maybe String)) -> Request (Result (List ( String, List error )) ( form, List ( String, List error ) ))
        withDecoder expectFormField =
            Request.map2
                (combineWithDecoder field.name)
                (field.name
                    |> nonEmptyString
                    |> Maybe.map expectFormField
                    |> Maybe.withDefault (Request.succeed Nothing)
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
                (decoder expectFormField)
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
                            (\_ ->
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
                            (\( value, _ ) ->
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


{-| -}
append : Field error value view constraints -> Form error form view -> Form error form view
append (Field field) (Form fields decoder serverValidations modelToValue) =
    Form
        --(field :: fields)
        (addField field fields)
        decoder
        serverValidations
        modelToValue


{-| -}
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


{-| -}
appendForm : (form1 -> form2 -> form) -> Form error form1 view -> Form error form2 view -> Form error form view
appendForm mapFn (Form fields1 decoder1 serverValidations1 modelToValue1) (Form fields2 decoder2 serverValidations2 modelToValue2) =
    Form
        -- TODO is this ordering correct?
        (fields1 ++ fields2)
        (\expectFormField ->
            Request.map2
                (map2ResultWithErrors mapFn)
                (decoder1 expectFormField)
                (decoder2 expectFormField)
        )
        (\expectFormField ->
            Request.map2
                (DataSource.map2 (++))
                (serverValidations1 expectFormField)
                (serverValidations2 expectFormField)
        )
        (\model ->
            map2ResultWithErrors mapFn
                (modelToValue1 model)
                (modelToValue2 model)
        )


{-| -}
wrap : (List view -> view) -> Form error form view -> Form error form view
wrap newWrapFn (Form fields decoder serverValidations modelToValue) =
    Form (wrapFields fields newWrapFn) decoder serverValidations modelToValue


{-| -}
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


{-| -}
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


{-| -}
toHtml2 :
    { makeHttpRequest : List ( String, String ) -> msg
    }
    -> (List (Html.Attribute msg) -> List view -> view)
    -> Model
    -> Form String value view
    -> view
toHtml2 config toForm serverValidationErrors (Form fields decoder serverValidations modelToValue) =
    let
        hasErrors_ : Bool
        hasErrors_ =
            hasErrors2 serverValidationErrors
    in
    toForm
        ([ [ Attr.method "POST" ]
         , [ Attr.novalidate True
           , FormDecoder.formDataOnSubmit |> Attr.map config.makeHttpRequest
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
        (\_ errors ->
            errors
                |> DataSource.map
                    (\validationErrors ->
                        if hasErrors validationErrors then
                            Server.Response.json
                                (validationErrors |> encodeErrors)

                        else
                            Server.Response.json
                                (validationErrors |> encodeErrors)
                    )
        )
        (Request.expectFormPost
            (\{ field } ->
                decoder (\string -> field string |> Request.map Just)
            )
        )
        (Request.expectFormPost
            (\{ field } ->
                serverValidations (\string -> field string |> Request.map Just)
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
toRequest2 ((Form fields decoder serverValidations modelToValue) as form) =
    Request.map2
        (\decoded errors ->
            errors
                |> DataSource.map
                    (\model ->
                        case decoded of
                            Ok ( value, otherValidationErrors ) ->
                                if
                                    otherValidationErrors
                                        |> List.any
                                            (\( _, entryErrors ) ->
                                                entryErrors |> List.isEmpty
                                            )
                                then
                                    Ok ( model, value )

                                else
                                    Err model

                            Err _ ->
                                Err model
                    )
        )
        (Request.expectFormPost
            (\{ field } ->
                decoder (\fieldName -> field fieldName |> Request.map Just)
            )
        )
        (Request.expectFormPost
            (\{ field } ->
                serverValidations (\string -> field string |> Request.map Just)
                    |> Request.map
                        (DataSource.map
                            (\thing ->
                                let
                                    fullFieldState : Dict String (RawFieldState String)
                                    fullFieldState =
                                        thing
                                            |> Dict.fromList
                                            |> Dict.map
                                                (\fieldName fieldValue ->
                                                    { fieldValue
                                                        | errors =
                                                            runValidation form
                                                                { name = fieldName
                                                                , value = fieldValue.raw |> Maybe.withDefault ""
                                                                }
                                                    }
                                                )

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


{-| -}
submitHandlers :
    Form String decoded view
    -> (Model -> Result () decoded -> DataSource data)
    -> Request (DataSource (PageServerResponse data))
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
                                        Err ()
                                            |> toDataSource model
                            )
                        -- TODO allow customizing headers or status code, or not?
                        |> DataSource.map Server.Response.render
                )
        ]


{-| -}
submitHandlers2 :
    Form String decoded view
    -> (Model -> Result () decoded -> DataSource (PageServerResponse data))
    -> Request (DataSource (PageServerResponse data))
submitHandlers2 myForm toDataSource =
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
                                        Err ()
                                            |> toDataSource model
                            )
                 -- TODO allow customizing headers or status code, or not?
                )
        ]


hasErrors : List ( String, RawFieldState error ) -> Bool
hasErrors validationErrors =
    List.any
        (\( _, entry ) ->
            entry.errors |> List.isEmpty |> not
        )
        validationErrors


{-| -}
hasErrors2 : Model -> Bool
hasErrors2 model =
    Dict.Extra.any
        (\_ entry ->
            entry.errors |> List.isEmpty |> not
        )
        model.fields


{-| -}
isSubmitting : Model -> Bool
isSubmitting model =
    model.isSubmitting == Submitting
