module Pages.FormParser exposing (..)

import Dict exposing (Dict)
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
succeed value =
    Parser (\errors form -> ( Just value, Dict.empty ))


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
            (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
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
