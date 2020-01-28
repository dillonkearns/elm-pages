module BuildError exposing (BuildError, errorToString, errorsToString)

import TerminalText as Terminal


type alias BuildError =
    { title : String
    , message : List Terminal.Text
    , fatal : Bool
    }


errorsToString : List BuildError -> String
errorsToString errors =
    errors
        |> List.map errorToString
        |> String.join "\n\n"


errorToString : BuildError -> String
errorToString error =
    banner error.title
        ++ error.message
        |> Terminal.toString


banner : String -> List Terminal.Text
banner title =
    [ Terminal.cyan <|
        Terminal.text ("-- " ++ String.toUpper title ++ " ----------------------------------------------------- elm-pages")
    , Terminal.text "\n\n"
    ]
