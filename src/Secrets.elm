module Secrets exposing
    ( Value
    , lookup
    , map
    , maskedLookup
    , succeed
    , with
    )

import BuildError exposing (BuildError)
import Fuzzy
import SecretsDict exposing (SecretsDict)
import TerminalText as Terminal


type Value value
    = Value (SecretsDict -> Result (List BuildError) value)


lookup : SecretsDict -> Value a -> Result (List BuildError) a
lookup secrets (Value lookupSecrets) =
    lookupSecrets secrets


maskedLookup : Value value -> value
maskedLookup (Value lookupSecrets) =
    case lookupSecrets SecretsDict.masked of
        Ok value ->
            value

        Err error ->
            -- crash
            maskedLookup (Value lookupSecrets)


succeed : value -> Value value
succeed value =
    Value (\_ -> Ok value)


append : Value (List value) -> Value (List value) -> Value (List value)
append (Value lookupSecrets1) (Value lookupSecrets2) =
    Value
        (\secrets ->
            let
                secrets1 : Result (List BuildError) (List value)
                secrets1 =
                    lookupSecrets1 secrets

                secrets2 : Result (List BuildError) (List value)
                secrets2 =
                    lookupSecrets2 secrets
            in
            case ( secrets1, secrets2 ) of
                ( Ok value1, Ok value2 ) ->
                    Ok (value1 ++ value2)

                ( Ok value1, Err errors2 ) ->
                    Err errors2

                ( Err errors1, Ok value2 ) ->
                    Err errors1

                ( Err errors1, Err errors2 ) ->
                    Err (errors1 ++ errors2)
        )


buildError : String -> SecretsDict -> BuildError
buildError secretName secretsDict =
    let
        availableEnvironmentVariables =
            SecretsDict.available secretsDict
    in
    { title = "Missing Secret"
    , message =
        [ Terminal.text "I expected to find this Secret in your environment variables but didn't find a match:\n\nSecrets.get \""
        , Terminal.text secretName
        , Terminal.text "\"\n             "
        , Terminal.red <| Terminal.text (underlineText (secretName |> String.length))
        , Terminal.text "\n\nSo maybe "
        , Terminal.yellow <| Terminal.text secretName
        , Terminal.text " should be "
        , Terminal.green <| Terminal.text (sortMatches secretName availableEnvironmentVariables |> List.head |> Maybe.withDefault "")
        ]
    , fatal = True
    }


underlineText : Int -> String
underlineText length =
    if length == 0 then
        ""

    else
        "^" ++ underlineText (length - 1)


sortMatches missingSecret availableSecrets =
    let
        simpleMatch config separators needle hay =
            Fuzzy.match config separators needle hay |> .score
    in
    List.sortBy (simpleMatch [] [] missingSecret) availableSecrets


map : (valueA -> valueB) -> Value valueA -> Value valueB
map mapFunction (Value lookupSecrets) =
    Value
        (\secrets ->
            lookupSecrets secrets
                |> Result.map mapFunction
        )


with : String -> Value (String -> value) -> Value value
with newSecret (Value lookupSecrets) =
    Value <|
        \secrets ->
            case lookupSecrets secrets of
                Ok value ->
                    case SecretsDict.get newSecret secrets of
                        Just newValue ->
                            value newValue |> Ok

                        Nothing ->
                            Err [ buildError newSecret secrets ]

                Err error ->
                    case SecretsDict.get newSecret secrets of
                        Just newValue ->
                            Err error

                        Nothing ->
                            -- TODO add more errors
                            Err
                                (buildError newSecret secrets
                                    :: error
                                )
