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

        Err _ ->
            -- crash
            maskedLookup (Value lookupSecrets)


succeed : value -> Value value
succeed value =
    Value (\_ -> Ok value)


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
    , path = "" -- TODO wire in path here?
    , fatal = True
    }


underlineText : Int -> String
underlineText length =
    String.repeat length "^"


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
                        Just _ ->
                            Err error

                        Nothing ->
                            -- TODO add more errors
                            Err
                                (buildError newSecret secrets
                                    :: error
                                )
