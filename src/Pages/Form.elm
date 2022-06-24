module Pages.Form exposing
    ( Form(..), FieldErrors, HtmlForm, StyledHtmlForm
    , init
    , addErrors, toResult
    , field, hiddenField, hiddenKind
    , ParsedField, ok
    , andThen
    , Context, ViewField
    , renderHtml, renderStyledHtml
    , Method(..), SubmitStrategy(..)
    , parse, runOneOfServerSide, runServerSide
    , dynamic, HtmlSubForm
    , FieldDefinition(..)
    , fail, subGroup
    )

{-|


## Building a Form Parser

@docs Form, FieldErrors, HtmlForm, StyledHtmlForm

@docs init

@docs addErrors, toResult


## Adding Fields

@docs field, hiddenField, hiddenKind


## Combining Fields

@docs ParsedField, ok


### Managing Errors

@docs andThen


## View Functions

@docs Context, ViewField


## Rendering Forms

@docs renderHtml, renderStyledHtml


### Rendering Options

@docs Method, SubmitStrategy


## Running Parsers

@docs parse, runOneOfServerSide, runServerSide


## Dynamic Fields

@docs dynamic, HtmlSubForm


## Internal-Only?

@docs FieldDefinition

-}

import Dict exposing (Dict)
import Dict.Extra
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy
import Html.Styled
import Html.Styled.Attributes as StyledAttr
import Html.Styled.Lazy
import Json.Encode as Encode
import Pages.Field as Field exposing (Field(..))
import Pages.FormState as Form
import Pages.Msg
import Pages.Transition



--{-| -}
--type
--    ParseResult error decoded
--    -- TODO parse into both errors AND a decoded value
--    = Success decoded
--    | DecodedWithErrors (Dict String (List error)) decoded
--    | DecodeFailure (Dict String (List error))


{-| -}
initFormState : Form.FormState
initFormState =
    { fields = Dict.empty
    , submitAttempted = False
    }


{-| -}
type alias Context error data =
    { errors : FieldErrors error
    , isTransitioning : Bool
    , submitAttempted : Bool
    , data : data
    }



--mapResult : (parsed -> mapped) -> ( Maybe parsed, FieldErrors error ) -> ( Maybe mapped, FieldErrors error )
--mapResult function ( maybe, fieldErrors ) =
--    ( maybe |> Maybe.map function, fieldErrors )


{-| -}
init : combined -> (Context String data -> viewFn) -> Form String combined data (Context String data -> viewFn)
init fn viewFn =
    Form []
        (\maybeData formState ->
            { result = ( Just fn, Dict.empty )
            , view = viewFn
            }
        )
        (\_ -> [])


{-| -}
dynamic :
    (decider -> Form error parsed data (Context error data -> subView))
    ->
        Form
            error
            ((decider -> ( Maybe parsed, FieldErrors error )) -> combined)
            data
            (Context error data -> ((decider -> subView) -> combinedView))
    -> Form error combined data (Context error data -> combinedView)
dynamic forms formBuilder =
    Form []
        (\maybeData formState ->
            let
                toParser : decider -> { result : ( Maybe parsed, FieldErrors error ), view : Context error data -> subView }
                toParser decider =
                    case forms decider of
                        Form definitions parseFn toInitialValues ->
                            -- TODO need to include hidden form fields from `definitions` (should they be automatically rendered? Does that mean the view type needs to be hardcoded?)
                            parseFn maybeData formState

                myFn :
                    { result : ( Maybe combined, Dict String (List error) )
                    , view : Context error data -> combinedView
                    }
                myFn =
                    let
                        deciderToParsed : decider -> ( Maybe parsed, FieldErrors error )
                        deciderToParsed decider =
                            decider
                                |> toParser
                                |> .result

                        newThing :
                            { result :
                                ( Maybe
                                    ((decider -> ( Maybe parsed, FieldErrors error )) -> combined)
                                , Dict String (List error)
                                )
                            , view : Context error data -> (decider -> subView) -> combinedView
                            }
                        newThing =
                            case formBuilder of
                                Form definitions parseFn toInitialValues ->
                                    parseFn maybeData formState

                        anotherThing : Maybe combined
                        anotherThing =
                            Maybe.map2
                                (\thing1 thing2 -> thing1 |> thing2)
                                (Just deciderToParsed)
                                (newThing.result
                                    -- TODO are these errors getting dropped? Write a test case to check
                                    |> Tuple.first
                                )
                    in
                    { result =
                        ( anotherThing
                        , newThing.result |> Tuple.second
                        )
                    , view =
                        \fieldErrors ->
                            let
                                something2 : decider -> subView
                                something2 decider =
                                    fieldErrors
                                        |> (decider
                                                |> toParser
                                                |> .view
                                           )
                            in
                            newThing.view fieldErrors something2
                    }
            in
            myFn
        )
        (\_ -> [])


{-| -}
subGroup :
    Form error ( Maybe parsed, FieldErrors error ) data (Context error data -> subView)
    ->
        Form
            error
            ({ value : parsed } -> combined)
            data
            (Context error data -> (subView -> combinedView))
    -> Form error combined data (Context error data -> combinedView)
subGroup forms formBuilder =
    Form []
        (\maybeData formState ->
            let
                toParser : { result : ( Maybe ( Maybe parsed, FieldErrors error ), Dict String (List error) ), view : Context error data -> subView }
                toParser =
                    case forms of
                        Form definitions parseFn toInitialValues ->
                            -- TODO need to include hidden form fields from `definitions` (should they be automatically rendered? Does that mean the view type needs to be hardcoded?)
                            parseFn maybeData formState

                myFn :
                    { result : ( Maybe combined, Dict String (List error) )
                    , view : Context error data -> combinedView
                    }
                myFn =
                    let
                        deciderToParsed : ( Maybe parsed, FieldErrors error )
                        deciderToParsed =
                            toParser |> mergeResults

                        newThing : { result : ( Maybe ({ value : parsed } -> combined), Dict String (List error) ), view : Context error data -> subView -> combinedView }
                        newThing =
                            case formBuilder of
                                Form definitions parseFn toInitialValues ->
                                    parseFn maybeData formState

                        anotherThing : Maybe combined
                        anotherThing =
                            Maybe.map2
                                (\runFn parsed ->
                                    runFn { value = parsed }
                                )
                                (Tuple.first newThing.result)
                                (deciderToParsed |> Tuple.first)
                    in
                    { result =
                        ( anotherThing
                        , mergeErrors (newThing.result |> Tuple.second)
                            (deciderToParsed |> Tuple.second)
                        )
                    , view =
                        \fieldErrors ->
                            let
                                something2 : subView
                                something2 =
                                    fieldErrors
                                        |> (toParser
                                                |> .view
                                           )
                            in
                            newThing.view fieldErrors something2
                    }
            in
            myFn
        )
        (\_ -> [])


{-| -}
andThen : (parsed -> ( Maybe combined, FieldErrors error )) -> ( Maybe parsed, FieldErrors error ) -> ( Maybe combined, FieldErrors error )
andThen andThenFn ( maybe, fieldErrors ) =
    case maybe of
        Just justValue ->
            andThenFn justValue
                |> Tuple.mapSecond (mergeErrors fieldErrors)

        Nothing ->
            ( Nothing, fieldErrors )


{-| -}
field :
    String
    -> Field error parsed data kind constraints
    -> Form error (ParsedField error parsed -> combined) data (Context error data -> (ViewField error parsed kind -> combinedView))
    -> Form error combined data (Context error data -> combinedView)
field name (Field fieldParser kind) (Form definitions parseFn toInitialValues) =
    Form
        (( name, RegularField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    fieldParser.decode rawFieldValue

                ( rawFieldValue, fieldStatus ) =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            ( Just info.value, info.status )

                        Nothing ->
                            ( Maybe.map2 (|>) maybeData fieldParser.initialValue, Form.NotVisited )

                parsedField : Maybe (ParsedField error parsed)
                parsedField =
                    maybeParsed
                        |> Maybe.map
                            (\parsed ->
                                { name = name
                                , value = parsed
                                , errors = errors
                                }
                            )

                rawField : ViewField error parsed kind
                rawField =
                    { name = name
                    , value = rawFieldValue
                    , status = fieldStatus
                    , kind = ( kind, fieldParser.properties )
                    , parsed = maybeParsed
                    , errors = errors
                    }

                myFn :
                    { result :
                        ( Maybe (ParsedField error parsed -> combined)
                        , Dict String (List error)
                        )
                    , view : Context error data -> ViewField error parsed kind -> combinedView
                    }
                    ->
                        { result : ( Maybe combined, Dict String (List error) )
                        , view : Context error data -> combinedView
                        }
                myFn soFar =
                    let
                        ( fieldThings, errorsSoFar ) =
                            soFar.result
                    in
                    { result =
                        ( case fieldThings of
                            Just fieldPipelineFn ->
                                parsedField
                                    |> Maybe.map fieldPipelineFn

                            Nothing ->
                                Nothing
                        , errorsSoFar
                            |> addErrorsInternal name errors
                        )
                    , view = \fieldErrors -> soFar.view fieldErrors rawField
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| -}
hiddenField :
    String
    -> Field error parsed data kind constraints
    -> Form error (ParsedField error parsed -> combined) data (Context error data -> combinedView)
    -> Form error combined data (Context error data -> combinedView)
hiddenField name (Field fieldParser kind) (Form definitions parseFn toInitialValues) =
    Form
        (( name, HiddenField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    fieldParser.decode rawFieldValue

                rawFieldValue : Maybe String
                rawFieldValue =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            Just info.value

                        Nothing ->
                            Maybe.map2 (|>) maybeData fieldParser.initialValue

                parsedField : Maybe (ParsedField error parsed)
                parsedField =
                    maybeParsed
                        |> Maybe.map
                            (\parsed ->
                                { name = name
                                , value = parsed
                                , errors = errors
                                }
                            )

                myFn :
                    { result :
                        ( Maybe (ParsedField error parsed -> combined)
                        , Dict String (List error)
                        )
                    , view : Context error data -> combinedView
                    }
                    ->
                        { result : ( Maybe combined, Dict String (List error) )
                        , view : Context error data -> combinedView
                        }
                myFn soFar =
                    let
                        ( fieldThings, errorsSoFar ) =
                            soFar.result
                    in
                    { result =
                        ( case fieldThings of
                            Just fieldPipelineFn ->
                                parsedField
                                    |> Maybe.map fieldPipelineFn

                            Nothing ->
                                Nothing
                        , errorsSoFar
                            |> addErrorsInternal name errors
                        )

                    -- TODO pass in `rawField` or similar to the hiddenFields (need the raw data to render it)
                    , view = \fieldErrors -> soFar.view fieldErrors
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| -}
hiddenKind :
    ( String, String )
    -> error
    -> Form error combined data (Context error data -> combinedView)
    -> Form error combined data (Context error data -> combinedView)
hiddenKind ( name, value ) error_ (Form definitions parseFn toInitialValues) =
    let
        (Field fieldParser kind) =
            Field.exactValue value error_
    in
    Form
        (( name, HiddenField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    fieldParser.decode rawFieldValue

                rawFieldValue : Maybe String
                rawFieldValue =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            Just info.value

                        Nothing ->
                            Maybe.map2 (|>) maybeData fieldParser.initialValue

                myFn :
                    { result :
                        ( Maybe combined
                        , Dict String (List error)
                        )
                    , view : Context error data -> combinedView
                    }
                    ->
                        { result : ( Maybe combined, Dict String (List error) )
                        , view : Context error data -> combinedView
                        }
                myFn soFar =
                    let
                        ( fieldThings, errorsSoFar ) =
                            soFar.result
                    in
                    { result =
                        ( fieldThings
                        , errorsSoFar |> addErrorsInternal name errors
                        )
                    , view = \fieldErrors -> soFar.view fieldErrors
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| -}
type alias FieldErrors error =
    Dict String (List error)


{-| -}
type alias AppContext app =
    { app
        | --, sharedData : Shared.Data
          --, routeParams : routeParams
          --, path : Path
          --, action : Maybe action
          --, submit :
          --    { fields : List ( String, String ), headers : List ( String, String ) }
          --    -> Pages.Fetcher.Fetcher (Result Http.Error action)
          transition : Maybe Pages.Transition.Transition
        , fetchers : List Pages.Transition.FetcherState
        , pageFormState : Form.PageFormState
    }


mergeResults :
    { a | result : ( Maybe ( Maybe parsed, Dict comparable (List error) ), Dict comparable (List error) ) }
    -> ( Maybe parsed, Dict comparable (List error) )
mergeResults parsed =
    case parsed.result of
        ( Just ( parsedThing, combineErrors ), individualFieldErrors ) ->
            ( parsedThing
            , mergeErrors combineErrors individualFieldErrors
            )

        ( Nothing, individualFieldErrors ) ->
            ( Nothing, individualFieldErrors )


mergeErrors : Dict comparable (List value) -> Dict comparable (List value) -> Dict comparable (List value)
mergeErrors errors1 errors2 =
    Dict.merge
        (\key entries soFar ->
            soFar |> insertIfNonempty key entries
        )
        (\key entries1 entries2 soFar ->
            soFar |> insertIfNonempty key (entries1 ++ entries2)
        )
        (\key entries soFar ->
            soFar |> insertIfNonempty key entries
        )
        errors1
        errors2
        Dict.empty


{-| -}
parse :
    AppContext app
    -> data
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error data -> view)
    -> ( Maybe parsed, FieldErrors error )
parse app data (Form fieldDefinitions parser _) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        --parsed : { result : ( Maybe parsed, FieldErrors error ), view : Context error -> view }
        parsed : { result : ( Maybe ( Maybe parsed, FieldErrors error ), Dict String (List error) ), view : Context error data -> view }
        parsed =
            parser (Just data) thisFormState

        thisFormState : Form.FormState
        thisFormState =
            app.pageFormState
                |> Dict.get "test"
                |> Maybe.withDefault initFormState
    in
    parsed |> mergeResults


insertIfNonempty : comparable -> List value -> Dict comparable (List value) -> Dict comparable (List value)
insertIfNonempty key values dict =
    if values |> List.isEmpty then
        dict

    else
        dict
            |> Dict.insert key values


{-| -}
runServerSide :
    List ( String, String )
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error data -> view)
    -> ( Maybe parsed, FieldErrors error )
runServerSide rawFormData (Form fieldDefinitions parser _) =
    let
        parsed : { result : ( Maybe ( Maybe parsed, FieldErrors error ), Dict String (List error) ), view : Context error data -> view }
        parsed =
            parser Nothing thisFormState

        thisFormState : Form.FormState
        thisFormState =
            { initFormState
                | fields =
                    rawFormData
                        |> List.map
                            (Tuple.mapSecond
                                (\value ->
                                    { value = value
                                    , status = Form.NotVisited
                                    }
                                )
                            )
                        |> Dict.fromList
            }
    in
    parsed |> mergeResults


{-| -}
runOneOfServerSide :
    List ( String, String )
    -> List (Form error ( Maybe parsed, FieldErrors error ) data (Context error data -> view))
    -> ( Maybe parsed, FieldErrors error )
runOneOfServerSide rawFormData parsers =
    case parsers of
        firstParser :: remainingParsers ->
            let
                thing : ( Maybe parsed, List ( String, List error ) )
                thing =
                    runServerSide rawFormData firstParser
                        |> Tuple.mapSecond
                            (\errors ->
                                errors
                                    |> Dict.toList
                                    |> List.filter (Tuple.second >> List.isEmpty >> not)
                            )
            in
            case thing of
                ( Just parsed, [] ) ->
                    ( Just parsed, Dict.empty )

                _ ->
                    runOneOfServerSide rawFormData remainingParsers

        [] ->
            -- TODO need to pass errors
            ( Nothing, Dict.empty )


{-| -}
renderHtml :
    RenderOptions
    -> AppContext app
    -> data
    ->
        Form
            error
            ( Maybe parsed, FieldErrors error )
            data
            (Context error data
             -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            )
    -> Html (Pages.Msg.Msg msg)
renderHtml options app data combinedParser =
    Html.Lazy.lazy4 renderHelper options app data combinedParser


{-| -}
renderStyledHtml :
    AppContext app
    -> data
    ->
        Form
            error
            ( Maybe parsed, FieldErrors error )
            data
            (Context error data
             -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) )
            )
    -> Html.Styled.Html (Pages.Msg.Msg msg)
renderStyledHtml app data combinedParser =
    Html.Styled.Lazy.lazy3 renderStyledHelper app data combinedParser


renderHelper :
    RenderOptions
    -> AppContext app
    -> data
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error data -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) ))
    -> Html (Pages.Msg.Msg msg)
renderHelper options formState data (Form fieldDefinitions parser toInitialValues) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        formId : String
        formId =
            -- TODO remove hardcoding
            "test"

        initialValues : Dict String Form.FieldState
        initialValues =
            toInitialValues data
                |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
                |> Dict.fromList

        part2 : Dict String Form.FieldState
        part2 =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault initFormState
                |> .fields

        fullFormState : Dict String Form.FieldState
        fullFormState =
            initialValues
                |> Dict.union part2

        parsed :
            { result : ( Maybe ( Maybe parsed, FieldErrors error ), Dict String (List error) )
            , view : Context error data -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            }
        parsed =
            parser (Just data) thisFormState

        merged : ( Maybe parsed, Dict String (List error) )
        merged =
            mergeResults parsed

        thisFormState : Form.FormState
        thisFormState =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault Form.init
                |> (\state -> { state | fields = fullFormState })

        context : Context error data
        context =
            { errors =
                merged |> Tuple.second
            , isTransitioning =
                case formState.transition of
                    Just transition ->
                        -- TODO need to track the form's ID and check that to see if it's *this*
                        -- form that is submitting
                        --transition.todo == formId
                        True

                    Nothing ->
                        False
            , submitAttempted = thisFormState.submitAttempted
            , data = data
            }

        ( formAttributes, children ) =
            parsed.view context

        hiddenInputs : List (Html (Pages.Msg.Msg msg))
        hiddenInputs =
            fieldDefinitions
                |> List.filterMap
                    (\( name, fieldDefinition ) ->
                        case fieldDefinition of
                            HiddenField ->
                                Just
                                    (Html.input
                                        [ Attr.name name
                                        , Attr.type_ "hidden"
                                        , Attr.value
                                            (initialValues
                                                |> Dict.get name
                                                |> Maybe.map .value
                                                |> Maybe.withDefault ""
                                            )
                                        ]
                                        []
                                    )

                            RegularField ->
                                Nothing
                    )
    in
    Html.form
        (Form.listeners formId
            ++ [ Attr.method (methodToString options.method)
               , Attr.novalidate True
               , case options.submitStrategy of
                    FetcherStrategy ->
                        Pages.Msg.fetcherOnSubmit (isValid parser data)

                    TransitionStrategy ->
                        Pages.Msg.submitIfValid (isValid parser data)
               ]
            ++ formAttributes
        )
        (hiddenInputs ++ children)


isValid : (Maybe data -> Form.FormState -> { a | result : ( Maybe parsed, FieldErrors error ) }) -> data -> List ( String, String ) -> Bool
isValid parser data fields =
    case
        { initFormState
            | fields =
                fields
                    |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
                    |> Dict.fromList
        }
            |> parser (Just data)
            -- TODO use mergedResults here
            |> .result
            |> toResult
    of
        Ok _ ->
            True

        Err _ ->
            False


renderStyledHelper :
    AppContext app
    -> data
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error data -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) ))
    -> Html.Styled.Html (Pages.Msg.Msg msg)
renderStyledHelper formState data (Form fieldDefinitions parser toInitialValues) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        formId : String
        formId =
            -- TODO remove hardcoding
            "test"

        initialValues : Dict String Form.FieldState
        initialValues =
            toInitialValues data
                |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
                |> Dict.fromList

        part2 : Dict String Form.FieldState
        part2 =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault initFormState
                |> .fields

        fullFormState : Dict String Form.FieldState
        fullFormState =
            initialValues
                |> Dict.union part2

        parsed :
            { result : ( Maybe ( Maybe parsed, FieldErrors error ), Dict String (List error) )
            , view : Context error data -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) )
            }
        parsed =
            parser (Just data) thisFormState

        merged : ( Maybe parsed, Dict String (List error) )
        merged =
            mergeResults parsed

        thisFormState : Form.FormState
        thisFormState =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault Form.init
                |> (\state -> { state | fields = fullFormState })

        context : Context error data
        context =
            { errors =
                merged |> Tuple.second
            , isTransitioning =
                case formState.transition of
                    Just transition ->
                        -- TODO need to track the form's ID and check that to see if it's *this*
                        -- form that is submitting
                        --transition.todo == formId
                        True

                    Nothing ->
                        False
            , submitAttempted = thisFormState.submitAttempted
            , data = data
            }

        ( formAttributes, children ) =
            parsed.view context

        hiddenInputs : List (Html.Styled.Html (Pages.Msg.Msg msg))
        hiddenInputs =
            fieldDefinitions
                |> List.filterMap
                    (\( name, fieldDefinition ) ->
                        case fieldDefinition of
                            HiddenField ->
                                Just
                                    (Html.Styled.input
                                        ([ Attr.name name
                                         , Attr.type_ "hidden"
                                         , Attr.value
                                            (initialValues
                                                |> Dict.get name
                                                |> Maybe.map .value
                                                |> Maybe.withDefault ""
                                            )
                                         ]
                                            |> List.map StyledAttr.fromUnstyled
                                        )
                                        []
                                    )

                            RegularField ->
                                Nothing
                    )
    in
    Html.Styled.form
        ((Form.listeners formId |> List.map StyledAttr.fromUnstyled)
            ++ [ -- TODO remove hardcoded method - make it part of the config for the form? Should the default be POST?
                 StyledAttr.method "POST"
               , StyledAttr.novalidate True
               , -- TODO need to make an option to choose `Pages.Msg.fetcherOnSubmit`
                 -- TODO `Pages.Msg.fetcherOnSubmit` needs to accept an `isValid` param, too
                 StyledAttr.fromUnstyled <|
                    Pages.Msg.submitIfValid
                        (\fields ->
                            case
                                { initFormState
                                    | fields =
                                        fields
                                            |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
                                            |> Dict.fromList
                                }
                                    |> parser (Just data)
                                    -- TODO use mergedResults here
                                    |> .result
                                    |> toResult
                            of
                                Ok _ ->
                                    True

                                Err _ ->
                                    False
                        )
               ]
            ++ formAttributes
        )
        (hiddenInputs ++ children)


{-| -}
toResult : ( Maybe parsed, FieldErrors error ) -> Result (FieldErrors error) parsed
toResult ( maybeParsed, fieldErrors ) =
    let
        isEmptyDict : Bool
        isEmptyDict =
            if Dict.isEmpty fieldErrors then
                True

            else
                fieldErrors
                    |> Dict.Extra.any (\_ errors -> List.isEmpty errors)
    in
    case ( maybeParsed, isEmptyDict ) of
        ( Just parsed, True ) ->
            Ok parsed

        _ ->
            Err fieldErrors


{-| -}
type alias HtmlForm error parsed data msg =
    Form
        error
        ( Maybe parsed, FieldErrors error )
        data
        (Context error data -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) ))


{-| -}
type alias HtmlSubForm error parsed data msg =
    Form
        error
        ( Maybe parsed, FieldErrors error )
        data
        (Context error data -> List (Html (Pages.Msg.Msg msg)))


{-| -}
type alias StyledHtmlForm error parsed data msg =
    Form
        error
        ( Maybe parsed, FieldErrors error )
        data
        (Context error data -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) ))


{-| -}
type Form error parsed data view
    = Form
        -- TODO for renderCustom, pass them as an argument with all hidden fields that the user must render
        (List ( String, FieldDefinition ))
        (Maybe data
         -> Form.FormState
         ->
            { result :
                ( Maybe parsed
                , Dict String (List error)
                )
            , view : view
            }
        )
        (data -> List ( String, String ))


type alias RenderOptions =
    { submitStrategy : SubmitStrategy
    , method : Method
    }


{-| -}
type Method
    = Post
    | Get


methodToString : Method -> String
methodToString method =
    case method of
        Post ->
            "POST"

        Get ->
            "GET"


{-| -}
type SubmitStrategy
    = FetcherStrategy
    | TransitionStrategy


{-| -}
type FieldDefinition
    = RegularField
    | HiddenField


{-| -}
type alias ParsedField error parsed =
    { name : String
    , value : parsed
    , errors : List error
    }


{-| -}
type alias ViewField error parsed kind =
    { name : String
    , value : Maybe String
    , status : Form.FieldStatus
    , kind : ( kind, List ( String, Encode.Value ) )
    , parsed : Maybe parsed
    , errors : List error
    }


{-| -}
ok : a -> ( Maybe a, FieldErrors error )
ok result =
    ( Just result, Dict.empty )


{-| -}
addErrorsInternal : String -> List error -> Dict String (List error) -> Dict String (List error)
addErrorsInternal name newErrors allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (newErrors ++ (errors |> Maybe.withDefault []))
            )


{-| -}
fail : ParsedField error parsed -> error -> ( Maybe combined, FieldErrors error )
fail { name } error =
    ( Nothing
    , Dict.fromList [ ( name, [ error ] ) ]
    )


{-| -}
addErrors : ParsedField error parsed -> List error -> Dict String (List error) -> Dict String (List error)
addErrors { name } newErrors allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (newErrors ++ (errors |> Maybe.withDefault []))
            )
