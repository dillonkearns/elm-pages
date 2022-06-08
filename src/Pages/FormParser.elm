module Pages.FormParser exposing (..)

import Dict exposing (Dict)
import Html
import Html.Attributes as Attr
import Pages.Form as Form


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


string : error -> FieldThing error String
string error =
    FieldThing
        (\fieldName formState ->
            let
                rawValue : Maybe String
                rawValue =
                    formState
                        |> Dict.get fieldName
                        |> Maybe.map .value
            in
            ( rawValue
            , []
            )
        )


requiredString : error -> FieldThing error String
requiredString error =
    FieldThing
        (\fieldName formState ->
            let
                rawValue : Maybe String
                rawValue =
                    formState
                        |> Dict.get fieldName
                        |> Maybe.map .value
            in
            if rawValue == Just "" || rawValue == Nothing then
                ( Nothing
                , [ error ]
                )

            else
                ( rawValue
                , []
                )
        )


andThenNew : combined -> viewFn -> CombinedParser String combined viewFn
andThenNew fn viewFn =
    CombinedParser []
        (\formState ->
            { result = ( Just fn, Dict.empty )
            , view = viewFn
            }
        )



--CombinedParser
--    []
--    (\formState ->
--        --let
--        --    something =
--        --        fn
--        --in
--        -- TODO use fn
--        ( Nothing, Dict.empty )
--    )


field :
    String
    -> FieldThing error parsed
    -> CombinedParser error (ParsedField error parsed -> combined) (RawField -> combinedView)
    -> CombinedParser error combined combinedView
field name (FieldThing fieldParser) (CombinedParser definitions parseFn) =
    CombinedParser
        (( name, FieldDefinition )
            :: definitions
        )
        (\formState ->
            let
                --something : ( Maybe parsed, List error )
                ( maybeParsed, errors ) =
                    fieldParser name formState

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
                    { name = name
                    , value = formState |> Dict.get name |> Maybe.map .value
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
                    , view : RawField -> combinedView
                    }
                    ->
                        { result : ( Maybe combined, Dict String (List error) )
                        , view : combinedView
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
                    , view = soFar.view rawField
                    }
            in
            formState
                |> parseFn
                |> myFn
        )



--field :
--    String
--    -> FieldThing error parsed
--    -> CombinedParser error ((ParsedField error parsed -> a) -> b)
--    -> CombinedParser error b
--field name fieldThing (CombinedParser definitions parseFn) =
--    --Debug.todo ""
--    let
--        myFn :
--            ( Maybe ((ParsedField error parsed -> a) -> b)
--            , Dict String (List error)
--            )
--            -> ( Maybe b, Dict String (List error) )
--        myFn ( fieldThings, errorsSoFar ) =
--            --Debug.todo ""
--            ( Nothing, errorsSoFar )
--    in
--    CombinedParser definitions
--        (\formState ->
--            formState
--                |> parseFn
--                |> myFn
--        )
--(List ( String, FieldDefinition )) (Form.FormState -> ( Maybe parsed, Dict String (List error) ))


type ParsingResult a
    = ParsingResult


type CompleteParser error parsed
    = CompleteParser


input attrs fieldThing =
    Html.input
        (attrs
            ++ [ Attr.value "TODO"

               -- TODO provide a way to get rawValue
               --fieldThing.rawValue
               ]
        )
        []


runNew :
    Form.FormState
    -> CombinedParser error parsed view
    ->
        { result : ( Maybe parsed, Dict String (List error) )
        , view : view
        }
runNew formState (CombinedParser fieldDefinitions parser) =
    --Debug.todo ""
    parser formState


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



--String
--  -> (a -> v)
--  -> Codec a
--  -> CustomCodec ((a -> Value) -> b) v
--  -> CustomCodec b v


type FieldThing error parsed
    = FieldThing (String -> Form.FormState -> ( Maybe parsed, List error ))


type FieldDefinition
    = FieldDefinition


type FullFieldThing error parsed
    = FullFieldThing { name : String } (Form.FormState -> parsed)



---> a1
---> a2
--field :
--    String
--    -> FieldThing error parsed
--    -> CombinedParser error ((FullFieldThing error parsed -> a) -> b)
--    -> CombinedParser error b
--field name fieldThing (CombinedParser definitions parseFn) =
--    --Debug.todo ""
--    let
--        myFn :
--            ( Maybe ((FullFieldThing error parsed -> a) -> b)
--            , Dict String (List error)
--            )
--            -> ( Maybe b, Dict String (List error) )
--        myFn ( fieldThings, errorsSoFar ) =
--            --Debug.todo ""
--            ( Nothing, errorsSoFar )
--    in
--    CombinedParser definitions
--        (\formState ->
--            formState
--                |> parseFn
--                |> myFn
--        )


type alias ParsedField error parsed =
    { name : String
    , value : parsed
    , errors : List error
    }


type alias RawField =
    { name : String
    , value : Maybe String
    }


value : FullFieldThing error parsed -> parsed
value =
    Debug.todo ""



--ok : parsed -> FullFieldThing error parsed
--ok okValue =
--    --Debug.todo ""
--    FullFieldThing { name = "TODO" } (\_ -> okValue)


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
