module Pages.FormParser exposing
    ( Context, FieldErrors, HtmlForm, ParsedField, RawField, addError, addErrors, andThenNew, field, hiddenField, hiddenKind, init, input, ok, render, renderHelper, renderHtml, runNew, runOneOfServerSide, runServerSide, toResult, withError
    , CombinedParser(..), CompleteParser(..), FieldDefinition(..), InputType(..), ParseResult(..), ParsingResult(..), TextType(..)
    )

{-|

@docs CombinedParser, CompleteParser, Context, FieldDefinition, FieldErrors, HtmlForm, InputType, ParseResult, ParsedField, ParsingResult, RawField, TextType, addError, addErrors, andThenNew, field, hiddenField, hiddenKind, init, input, ok, render, renderHelper, renderHtml, runNew, runOneOfServerSide, runServerSide, toResult, withError

-}

import Dict exposing (Dict)
import Dict.Extra
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy
import Json.Encode as Encode
import Pages.Field as Field exposing (Field(..))
import Pages.FieldRenderer
import Pages.Form as Form
import Pages.Msg
import Pages.Transition


{-| -}
type
    ParseResult error decoded
    -- TODO parse into both errors AND a decoded value
    = Success decoded
    | DecodedWithErrors (Dict String (List error)) decoded
    | DecodeFailure (Dict String (List error))


{-| -}
init : Form.FormState
init =
    { fields = Dict.empty
    , submitAttempted = False
    }


{-| -}
type alias Context error =
    { errors : FieldErrors error
    , isTransitioning : Bool
    , submitAttempted : Bool
    }


{-| -}
andThenNew : combined -> (Context String -> viewFn) -> CombinedParser String combined data (Context String -> viewFn)
andThenNew fn viewFn =
    CombinedParser []
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
    -> CombinedParser error (ParsedField error parsed -> combined) data (Context error -> (RawField kind -> combinedView))
    -> CombinedParser error combined data (Context error -> combinedView)
field name (Field fieldParser kind) (CombinedParser definitions parseFn toInitialValues) =
    CombinedParser
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

                rawField : RawField kind
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
                    , view : Context error -> RawField kind -> combinedView
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
    -> CombinedParser error (ParsedField error parsed -> combined) data (Context error -> combinedView)
    -> CombinedParser error combined data (Context error -> combinedView)
hiddenField name (Field fieldParser kind) (CombinedParser definitions parseFn toInitialValues) =
    CombinedParser
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

                rawField : RawField ()
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
    -> CombinedParser error combined data (Context error -> combinedView)
    -> CombinedParser error combined data (Context error -> combinedView)
hiddenKind ( name, value ) error_ (CombinedParser definitions parseFn toInitialValues) =
    let
        (Field fieldParser kind) =
            Field.exactValue value error_
    in
    CombinedParser
        (( name, HiddenField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    fieldParser.decode rawField.value

                rawField : RawField ()
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
type ParsingResult a
    = ParsingResult


{-| -}
type CompleteParser error parsed
    = CompleteParser


{-| -}
type InputType
    = Text TextType
    | TextArea
    | Radio
    | Checkbox
    | Select (List ( String, String ))


{-| -}
type TextType
    = Phone


{-| -}
input : List (Html.Attribute msg) -> RawField Pages.FieldRenderer.Input -> Html msg
input attrs rawField =
    Html.input
        (attrs
            -- TODO need to handle other input types like checkbox
            ++ [ Attr.value (rawField.value |> Maybe.withDefault "") -- TODO is this an okay default?
               , Attr.name rawField.name
               ]
        )
        []


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


{-| -}
runNew :
    AppContext app
    -> data
    -> CombinedParser error parsed data (Context error -> view)
    ->
        { result : ( Maybe parsed, FieldErrors error )
        , view : view
        }
runNew app data (CombinedParser fieldDefinitions parser _) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        parsed : { result : ( Maybe parsed, FieldErrors error ), view : Context error -> view }
        parsed =
            parser (Just data) thisFormState

        thisFormState : Form.FormState
        thisFormState =
            app.pageFormState
                |> Dict.get "test"
                |> Maybe.withDefault init

        context =
            { errors =
                parsed.result |> Tuple.second
            , isTransitioning = False
            , submitAttempted = thisFormState.submitAttempted
            }
    in
    { result = parsed.result
    , view = parsed.view context
    }


{-| -}
runServerSide :
    List ( String, String )
    -> CombinedParser error parsed data (Context error -> view)
    -> ( Maybe parsed, FieldErrors error )
runServerSide rawFormData (CombinedParser fieldDefinitions parser _) =
    let
        parsed : { result : ( Maybe parsed, FieldErrors error ), view : Context error -> view }
        parsed =
            parser Nothing thisFormState

        thisFormState : Form.FormState
        thisFormState =
            { init
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
    parsed.result


{-| -}
runOneOfServerSide :
    List ( String, String )
    -> List (CombinedParser error parsed data (Context error -> view))
    -> ( Maybe parsed, FieldErrors error )
runOneOfServerSide rawFormData parsers =
    case parsers of
        firstParser :: remainingParsers ->
            let
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



--Debug.todo ""
--let
--    parsed : { result : ( Maybe parsed, FieldErrors error ), view : Context error -> view }
--    parsed =
--        parser Nothing thisFormState
--
--    thisFormState : Form.FormState
--    thisFormState =
--        { init
--            | fields =
--                rawFormData
--                    |> List.map
--                        (Tuple.mapSecond
--                            (\value ->
--                                { value = value
--                                , status = Form.NotVisited
--                                }
--                            )
--                        )
--                    |> Dict.fromList
--        }
--
--    context =
--        { errors = parsed.result |> Tuple.second
--        , isTransitioning = False
--        , submitAttempted = False
--        }
--in
--{ result = parsed.result
--, view = parsed.view context
--}


{-| -}
renderHtml :
    AppContext app
    -> data
    ->
        CombinedParser
            error
            parsed
            data
            (Context error
             -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            )
    -> Html (Pages.Msg.Msg msg)
renderHtml app data combinedParser =
    Html.Lazy.lazy3 renderHelper app data combinedParser



--renderStyledHtml :
--    AppContext app data
--    ->
--        CombinedParser
--            error
--            parsed
--            data
--            (Context error
--             -> ( List (Html.Styled.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
--            )
--    -> Html (Pages.Msg.Msg msg)
--renderStyledHtml formState_ combinedParser =
--    Html.Lazy.lazy2 renderHelper formState_ combinedParser


{-| -}
renderHelper :
    AppContext app
    -> data
    ->
        CombinedParser
            error
            parsed
            data
            (Context error
             -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            )
    -> Html (Pages.Msg.Msg msg)
renderHelper formState data (CombinedParser fieldDefinitions parser toInitialValues) =
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
                |> Maybe.withDefault init
                |> .fields

        fullFormState : Dict String Form.FieldState
        fullFormState =
            initialValues
                |> Dict.union part2

        parsed :
            { result : ( Maybe parsed, Dict String (List error) )
            , view : Context error -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            }
        parsed =
            parser (Just data) thisFormState

        thisFormState : Form.FormState
        thisFormState =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault Form.init
                |> (\state -> { state | fields = fullFormState })

        context =
            { errors =
                parsed.result |> Tuple.second
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
                            { init
                                | fields =
                                    fields
                                        |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
                                        |> Dict.fromList
                            }
                                |> parser (Just data)
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
render :
    AppContext app
    -> data
    -> CombinedParser error parsed data (Context error -> view)
    -> view
render formState data (CombinedParser fieldDefinitions parser toInitialValues) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        formId : String
        formId =
            -- TODO remove hardcoding
            "test"

        parsed :
            { result : ( Maybe parsed, FieldErrors error )
            , view : Context error -> view
            }
        parsed =
            parser (Just data) thisFormState

        thisFormState : Form.FormState
        thisFormState =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault Form.init

        context =
            { errors =
                parsed.result |> Tuple.second
            , isTransitioning =
                case formState.transition of
                    Just transition ->
                        -- TODO need to track the form's ID and check that to see if it's *this*
                        -- form that is submitting
                        --transition.todo == formId
                        True

                    --True
                    Nothing ->
                        False
            , submitAttempted = thisFormState.submitAttempted
            }
    in
    parsed.view context


{-| -}
type alias HtmlForm error parsed data msg =
    CombinedParser
        error
        parsed
        data
        (Context error -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) ))


{-| -}
type CombinedParser error parsed data view
    = CombinedParser
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
type alias RawField kind =
    { name : String
    , value : Maybe String
    , status : Form.FieldStatus
    , kind : ( kind, List ( String, Encode.Value ) )
    }


{-| -}
ok : a -> a
ok result =
    result


{-| -}
withError : error -> ParsedField error parsed -> ()
withError _ _ =
    --Debug.todo ""
    ()


{-| -}
addError : String -> error -> Dict String (List error) -> Dict String (List error)
addError name error allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (error :: (errors |> Maybe.withDefault []))
            )


{-| -}
addErrors : String -> List error -> Dict String (List error) -> Dict String (List error)
addErrors name newErrors allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (newErrors ++ (errors |> Maybe.withDefault []))
            )
