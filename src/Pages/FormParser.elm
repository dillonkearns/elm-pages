module Pages.FormParser exposing
    ( Form(..), FieldErrors, HtmlForm, StyledHtmlForm
    , init
    , addErrors, toResult
    , field, hiddenField, hiddenKind
    , ParsedField, ok
    , Context, ViewField
    , renderHtml, renderStyledHtml
    , runNew, runOneOfServerSide, runServerSide
    , FieldDefinition(..)
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


## View Functions

@docs Context, ViewField


## Rendering Forms

@docs renderHtml, renderStyledHtml


## Running Parsers

@docs runNew, runOneOfServerSide, runServerSide


## Internal-Only?

@docs FieldDefinition


## Unused?

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
import Pages.Form as Form
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
type alias Context error =
    { errors : FieldErrors error
    , isTransitioning : Bool
    , submitAttempted : Bool
    }



--mapResult : (parsed -> mapped) -> ( Maybe parsed, FieldErrors error ) -> ( Maybe mapped, FieldErrors error )
--mapResult function ( maybe, fieldErrors ) =
--    ( maybe |> Maybe.map function, fieldErrors )


{-| -}
init : combined -> (Context String -> viewFn) -> Form String combined data (Context String -> viewFn)
init fn viewFn =
    Form []
        (\maybeData formState ->
            { result = ( Just fn, Dict.empty )
            , view = viewFn
            }
        )
        (\_ -> [])


{-| -}
field :
    String
    -> Field error parsed data kind constraints
    -> Form error (ParsedField error parsed -> combined) data (Context error -> (ViewField kind -> combinedView))
    -> Form error combined data (Context error -> combinedView)
field name (Field fieldParser kind) (Form definitions parseFn toInitialValues) =
    Form
        (( name, RegularField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    fieldParser.decode rawField.value

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

                rawField : ViewField kind
                rawField =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            { name = name
                            , value = Just info.value
                            , status = info.status
                            , kind = ( kind, fieldParser.properties )
                            }

                        Nothing ->
                            { name = name
                            , value = Maybe.map2 (|>) maybeData fieldParser.initialValue
                            , status = Form.NotVisited
                            , kind = ( kind, fieldParser.properties )
                            }

                myFn :
                    { result :
                        ( Maybe (ParsedField error parsed -> combined)
                        , Dict String (List error)
                        )
                    , view : Context error -> ViewField kind -> combinedView
                    }
                    ->
                        { result : ( Maybe combined, Dict String (List error) )
                        , view : Context error -> combinedView
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
                            |> addErrors name errors
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
    -> Form error (ParsedField error parsed -> combined) data (Context error -> combinedView)
    -> Form error combined data (Context error -> combinedView)
hiddenField name (Field fieldParser kind) (Form definitions parseFn toInitialValues) =
    Form
        (( name, HiddenField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    fieldParser.decode rawField.value

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

                rawField : ViewField ()
                rawField =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            { name = name
                            , value = Just info.value
                            , status = info.status
                            , kind = ( (), [] )
                            }

                        Nothing ->
                            { name = name
                            , value = Maybe.map2 (|>) maybeData fieldParser.initialValue
                            , status = Form.NotVisited
                            , kind = ( (), [] )
                            }

                myFn :
                    { result :
                        ( Maybe (ParsedField error parsed -> combined)
                        , Dict String (List error)
                        )
                    , view : Context error -> combinedView
                    }
                    ->
                        { result : ( Maybe combined, Dict String (List error) )
                        , view : Context error -> combinedView
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
                            |> addErrors name errors
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
    -> Form error combined data (Context error -> combinedView)
    -> Form error combined data (Context error -> combinedView)
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
                    fieldParser.decode rawField.value

                rawField : ViewField ()
                rawField =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            { name = name
                            , value = Just info.value
                            , status = info.status
                            , kind = ( (), [] )
                            }

                        Nothing ->
                            { name = name
                            , value = Maybe.map2 (|>) maybeData fieldParser.initialValue
                            , status = Form.NotVisited
                            , kind = ( (), [] )
                            }

                myFn :
                    { result :
                        ( Maybe combined
                        , Dict String (List error)
                        )
                    , view : Context error -> combinedView
                    }
                    ->
                        { result : ( Maybe combined, Dict String (List error) )
                        , view : Context error -> combinedView
                        }
                myFn soFar =
                    let
                        ( fieldThings, errorsSoFar ) =
                            soFar.result
                    in
                    { result =
                        ( fieldThings
                        , errorsSoFar |> addErrors name errors
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


mergeResults parsed =
    case parsed.result of
        ( Just ( parsedThing, combineErrors ), individualFieldErrors ) ->
            ( parsedThing
            , Dict.merge
                (\key entries soFar ->
                    soFar |> insertIfNonempty key entries
                )
                (\key entries1 entries2 soFar ->
                    soFar |> insertIfNonempty key (entries1 ++ entries2)
                )
                (\key entries soFar ->
                    soFar |> insertIfNonempty key entries
                )
                combineErrors
                individualFieldErrors
                Dict.empty
            )

        ( Nothing, individualFieldErrors ) ->
            ( Nothing, individualFieldErrors )


{-| -}
runNew :
    AppContext app
    -> data
    ---> CombinedParser error parsed data (Context error -> view)
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error -> view)
    ->
        { result : ( Maybe parsed, FieldErrors error )
        , view : view
        }
runNew app data (Form fieldDefinitions parser _) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        --parsed : { result : ( Maybe parsed, FieldErrors error ), view : Context error -> view }
        parsed : { result : ( Maybe ( Maybe parsed, FieldErrors error ), Dict String (List error) ), view : Context error -> view }
        parsed =
            parser (Just data) thisFormState

        something =
            parsed |> mergeResults

        thisFormState : Form.FormState
        thisFormState =
            app.pageFormState
                |> Dict.get "test"
                |> Maybe.withDefault initFormState

        context =
            { errors =
                something |> Tuple.second
            , isTransitioning = False
            , submitAttempted = thisFormState.submitAttempted
            }
    in
    { result = something
    , view = parsed.view context
    }


insertIfNonempty key values dict =
    if values |> List.isEmpty then
        dict

    else
        dict
            |> Dict.insert key values


{-| -}
runServerSide :
    List
        ( String, String )
    ---> CombinedParser error parsed data (Context error -> view)
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error -> view)
    -> ( Maybe parsed, FieldErrors error )
runServerSide rawFormData (Form fieldDefinitions parser _) =
    let
        parsed : { result : ( Maybe ( Maybe parsed, FieldErrors error ), Dict String (List error) ), view : Context error -> view }
        parsed =
            parser Nothing thisFormState

        something =
            case parsed.result of
                ( Just ( parsedThing, combineErrors ), individualFieldErrors ) ->
                    ( parsedThing
                    , Dict.merge
                        (\key entries soFar ->
                            soFar |> insertIfNonempty key entries
                        )
                        (\key entries1 entries2 soFar ->
                            soFar |> insertIfNonempty key (entries1 ++ entries2)
                        )
                        (\key entries soFar ->
                            soFar |> insertIfNonempty key entries
                        )
                        combineErrors
                        individualFieldErrors
                        Dict.empty
                    )

                ( Nothing, individualFieldErrors ) ->
                    ( Nothing, individualFieldErrors )

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

        context =
            { errors = parsed.result |> Tuple.second
            , isTransitioning = False
            , submitAttempted = False
            }
    in
    something


{-| -}
runOneOfServerSide :
    List ( String, String )
    ---> List (CombinedParser error parsed data (Context error -> view))
    -> List (Form error ( Maybe parsed, FieldErrors error ) data (Context error -> view))
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
    AppContext app
    -> data
    ->
        Form
            error
            ( Maybe parsed, FieldErrors error )
            data
            (Context error
             -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            )
    -> Html (Pages.Msg.Msg msg)
renderHtml app data combinedParser =
    Html.Lazy.lazy3 renderHelper app data combinedParser


{-| -}
renderStyledHtml :
    AppContext app
    -> data
    ->
        Form
            error
            ( Maybe parsed, FieldErrors error )
            data
            (Context error
             -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) )
            )
    -> Html.Styled.Html (Pages.Msg.Msg msg)
renderStyledHtml app data combinedParser =
    Html.Styled.Lazy.lazy3 renderStyledHelper app data combinedParser


renderHelper :
    AppContext app
    -> data
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) ))
    -> Html (Pages.Msg.Msg msg)
renderHelper formState data (Form fieldDefinitions parser toInitialValues) =
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
            , view : Context error -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
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

        context : { errors : Dict String (List error), isTransitioning : Bool, submitAttempted : Bool }
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
            ++ [ -- TODO remove hardcoded method - make it part of the config for the form? Should the default be POST?
                 Attr.method "POST"
               , Attr.novalidate True
               , -- TODO need to make an option to choose `Pages.Msg.fetcherOnSubmit`
                 -- TODO `Pages.Msg.fetcherOnSubmit` needs to accept an `isValid` param, too
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


renderStyledHelper :
    AppContext app
    -> data
    -> Form error ( Maybe parsed, FieldErrors error ) data (Context error -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) ))
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
            , view : Context error -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) )
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

        context : { errors : Dict String (List error), isTransitioning : Bool, submitAttempted : Bool }
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
        (Context error -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) ))


{-| -}
type alias StyledHtmlForm error parsed data msg =
    Form
        error
        ( Maybe parsed, FieldErrors error )
        data
        (Context error -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html.Styled.Html (Pages.Msg.Msg msg)) ))


{-| -}
type Form error parsed data view
    = Form
        -- TODO track hidden fields here - for renderHtml and renderStyled, automatically render them
        -- TODO for renderCustom, pass them as an argument that the user must render
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
type alias ViewField kind =
    { name : String
    , value : Maybe String
    , status : Form.FieldStatus
    , kind : ( kind, List ( String, Encode.Value ) )
    }


{-| -}
ok : a -> ( Maybe a, FieldErrors error )
ok result =
    ( Just result, Dict.empty )


{-| -}
addErrors : String -> List error -> Dict String (List error) -> Dict String (List error)
addErrors name newErrors allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (newErrors ++ (errors |> Maybe.withDefault []))
            )
