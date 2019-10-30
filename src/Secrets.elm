module Secrets exposing (Secrets, get)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Fuzzy
import Pages.Internal.Secrets exposing (Secrets(..))
import TerminalText as Terminal


type alias Secrets =
    Pages.Internal.Secrets.Secrets


get : String -> Secrets -> Result BuildError String
get name secretsData =
    case secretsData of
        Protected ->
            Ok ("<" ++ name ++ ">")

        Secrets secrets ->
            case Dict.get name secrets of
                Just secret ->
                    Ok secret

                Nothing ->
                    Err <| buildError name (Dict.keys secrets)


buildError : String -> List String -> BuildError
buildError secretName availableEnvironmentVariables =
    { message =
        [ Terminal.text "I expected to find this Secret in your environment variables but didn't find a match:\n\nSecrets.get \""
        , Terminal.text secretName
        , Terminal.text "\"\n             "
        , Terminal.red <| Terminal.text (underlineText (secretName |> String.length))
        , Terminal.text "\n\nSo maybe "
        , Terminal.yellow <| Terminal.text secretName
        , Terminal.text " should be "
        , Terminal.green <| Terminal.text (sortMatches secretName availableEnvironmentVariables |> List.head |> Maybe.withDefault "")
        ]
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
