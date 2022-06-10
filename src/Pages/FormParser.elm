module Pages.FormParser exposing (..)

import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy
import Pages.Field as Field exposing (Field(..))
import Pages.Form as Form
import Pages.Msg
import Pages.Transition


type
    ParseResult error decoded
    -- TODO parse into both errors AND a decoded value
    = Success decoded
    | DecodedWithErrors (Dict String (List error)) decoded
    | DecodeFailure (Dict String (List error))


type Parser error decoded
    = Parser (Dict String (List error) -> Form.FormState -> ( Maybe decoded, Dict String (List error) ))


optional : String -> Parser error (Maybe String)
optional name =
    (\errors form ->
        ( Just (form |> Dict.get name |> Maybe.map .value), errors )
    )
        |> Parser


init =
    Debug.todo ""


type alias Context error =
    { errors : FieldErrors error
    , isTransitioning : Bool
    }


andThenNew : combined -> (Context String -> viewFn) -> CombinedParser String combined (Context String -> viewFn)
andThenNew fn viewFn =
    CombinedParser []
        (\formState ->
            { result = ( Just fn, Dict.empty )
            , view = viewFn
            }
        )


field :
    String
    -> Field error parsed constraints
    -> CombinedParser error (ParsedField error parsed -> combined) (Context error -> (RawField -> combinedView))
    -> CombinedParser error combined (Context error -> combinedView)
field name (Field fieldParser) (CombinedParser definitions parseFn) =
    CombinedParser
        (( name, FieldDefinition )
            :: definitions
        )
        (\formState ->
            let
                --something : ( Maybe parsed, List error )
                ( maybeParsed, errors ) =
                    fieldParser.decode (Dict.get name formState |> Maybe.map .value)

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

                rawField : RawField
                rawField =
                    case formState |> Dict.get name of
                        Just info ->
                            { name = name
                            , value = Just info.value
                            , status = info.status
                            }

                        Nothing ->
                            { name = name
                            , value = Nothing
                            , status = Form.NotVisited
                            }

                --{ result :
                --    ( Maybe parsed
                --    , Dict String (List error)
                --    )
                --, view : view
                --}
                myFn :
                    { result :
                        ( Maybe (ParsedField error parsed -> combined)
                        , Dict String (List error)
                        )
                    , view : Context error -> RawField -> combinedView
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
                |> parseFn
                |> myFn
        )


type ParsingResult a
    = ParsingResult


type CompleteParser error parsed
    = CompleteParser


input attrs rawField =
    Html.input
        (attrs
            -- TODO need to handle other input types like checkbox
            ++ [ Attr.value (rawField.value |> Maybe.withDefault "") -- TODO is this an okay default?
               , Attr.name rawField.name
               ]
        )
        []


type alias FieldErrors error =
    Dict String (List error)


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


runNew :
    Form.FormState
    -> CombinedParser error parsed (Context error -> view)
    ->
        { result : ( Maybe parsed, FieldErrors error )
        , view : view
        }
runNew formState (CombinedParser fieldDefinitions parser) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        --parsed :
        --    { result : ( Maybe parsed, FieldErrors error )
        --    , view : FieldErrors error -> view
        --    }
        parsed =
            parser formState

        context =
            { errors =
                parsed.result |> Tuple.second
            , isTransitioning = False
            }
    in
    { result = parsed.result
    , view = parsed.view context
    }


renderHtml :
    AppContext app
    ->
        CombinedParser
            error
            parsed
            (Context error
             -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            )
    -> Html (Pages.Msg.Msg msg)
renderHtml formState_ combinedParser =
    Html.Lazy.lazy2 renderHelper formState_ combinedParser


renderHelper :
    AppContext app
    ->
        CombinedParser
            error
            parsed
            (Context error
             -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            )
    -> Html (Pages.Msg.Msg msg)
renderHelper formState (CombinedParser fieldDefinitions parser) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        formId : String
        formId =
            -- TODO remove hardcoding
            "test"

        parsed :
            { result : ( Maybe parsed, Dict String (List error) )
            , view : Context error -> ( List (Html.Attribute (Pages.Msg.Msg msg)), List (Html (Pages.Msg.Msg msg)) )
            }
        parsed =
            parser
                (formState.pageFormState
                    |> Dict.get formId
                    |> Maybe.withDefault Dict.empty
                )

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
            }

        ( formAttributes, children ) =
            parsed.view context
    in
    Html.form
        (Form.listeners formId
            ++ [ -- TODO remove hardcoded method - make it part of the config for the form? Should the default be POST?
                 Attr.method "POST"
               , Pages.Msg.onSubmit
               ]
            ++ formAttributes
        )
        children


render :
    AppContext app
    -> CombinedParser error parsed (Context error -> view)
    -> view
render formState (CombinedParser fieldDefinitions parser) =
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
            parser
                (formState.pageFormState
                    |> Dict.get formId
                    |> Maybe.withDefault Dict.empty
                )

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
            }
    in
    parsed.view context


type CombinedParser error parsed view
    = CombinedParser
        (List ( String, FieldDefinition ))
        (Form.FormState
         ->
            { result :
                ( Maybe parsed
                , Dict String (List error)
                )
            , view : view
            }
        )


type FieldDefinition
    = FieldDefinition


type alias ParsedField error parsed =
    { name : String
    , value : parsed
    , errors : List error
    }


type alias RawField =
    { name : String
    , value : Maybe String
    , status : Form.FieldStatus
    }


ok result =
    result


withError : error -> ParsedField error parsed -> ()
withError _ _ =
    --Debug.todo ""
    ()


required : String -> error -> Parser error String
required name error =
    (\errors form ->
        case form |> Dict.get name |> Maybe.map .value of
            Just "" ->
                ( Just "", errors |> addError name error )

            Just nonEmptyValue ->
                ( Just nonEmptyValue, errors )

            Nothing ->
                ( Just "", errors |> addError name error )
    )
        |> Parser


int : String -> error -> Parser error Int
int name error =
    (\errors form ->
        case form |> Dict.get name |> Maybe.map .value of
            Just "" ->
                ( Nothing, errors |> addError name error )

            Just nonEmptyValue ->
                case nonEmptyValue |> String.toInt of
                    Just parsedInt ->
                        ( Just parsedInt, errors )

                    Nothing ->
                        ( Nothing, errors |> addError name error )

            Nothing ->
                ( Nothing, errors |> addError name error )
    )
        |> Parser


map2 : (value1 -> value2 -> combined) -> Parser error value1 -> Parser error value2 -> Parser error combined
map2 combineFn (Parser parser1) (Parser parser2) =
    (\errors form ->
        let
            ( combined1, allErrors1 ) =
                parser1 errors form

            ( combined2, allErrors2 ) =
                parser2 errors form
        in
        ( Maybe.map2 combineFn combined1 combined2
        , Dict.merge (\name errors1 dict -> ( name, errors1 ) :: dict)
            (\name errors1 errors2 dict -> ( name, errors1 ++ errors2 ) :: dict)
            (\name errors2 dict -> ( name, errors2 ) :: dict)
            allErrors1
            allErrors2
            []
            |> Dict.fromList
        )
    )
        |> Parser


map : (original -> mapped) -> Parser error original -> Parser error mapped
map mapFn (Parser parser) =
    (\errors form ->
        let
            ( combined1, allErrors1 ) =
                parser errors form
        in
        ( Maybe.map mapFn combined1
        , allErrors1
        )
    )
        |> Parser


validate : String -> (original -> Result error mapped) -> Parser error original -> Parser error mapped
validate name mapFn (Parser parser) =
    (\errors form ->
        let
            ( combined1, allErrors1 ) =
                parser errors form
        in
        case combined1 |> Maybe.map mapFn of
            Just (Ok okResult) ->
                ( Just okResult
                , allErrors1
                )

            Just (Err error) ->
                ( Nothing
                , allErrors1 |> addError name error
                )

            Nothing ->
                ( Nothing
                , allErrors1
                )
    )
        |> Parser


succeed : value -> Parser error value
succeed value_ =
    Parser (\errors form -> ( Just value_, Dict.empty ))


fail : error -> Parser error value
fail error =
    Parser (\errors form -> ( Nothing, Dict.fromList [ ( "global", [ error ] ) ] ))


andThen : (value1 -> Parser error value2) -> Parser error value1 -> Parser error value2
andThen andThenFn (Parser parser1) =
    (\errors form ->
        let
            ( combined1, allErrors1 ) =
                parser1 errors form

            foo : Maybe (Parser error value2)
            foo =
                Maybe.map andThenFn combined1
        in
        case foo of
            Just (Parser parser2) ->
                let
                    ( combined2, allErrors2 ) =
                        parser2 errors form
                in
                ( combined2
                , Dict.merge (\name errors1 dict -> ( name, errors1 ) :: dict)
                    (\name errors1 errors2 dict -> ( name, errors1 ++ errors2 ) :: dict)
                    (\name errors2 dict -> ( name, errors2 ) :: dict)
                    allErrors1
                    allErrors2
                    []
                    |> Dict.fromList
                )

            Nothing ->
                ( Nothing, allErrors1 )
    )
        |> Parser


run : Form.FormState -> Parser error decoded -> ( Maybe decoded, Dict String (List error) )
run formState (Parser parser) =
    parser Dict.empty formState


runOnList : List ( String, String ) -> Parser error decoded -> ( Maybe decoded, Dict String (List error) )
runOnList rawFormData (Parser parser) =
    (rawFormData
        |> List.map
            (Tuple.mapSecond (\value_ -> { value = value_, status = Form.NotVisited }))
        |> Dict.fromList
    )
        |> parser Dict.empty


addError : String -> error -> Dict String (List error) -> Dict String (List error)
addError name error allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (error :: (errors |> Maybe.withDefault []))
            )


addErrors : String -> List error -> Dict String (List error) -> Dict String (List error)
addErrors name newErrors allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (newErrors ++ (errors |> Maybe.withDefault []))
            )
