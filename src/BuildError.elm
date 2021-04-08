module BuildError exposing (BuildError, encode, errorToString, errorsToString)

import Json.Encode as Encode
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


encode : BuildError -> Encode.Value
encode buildError =
    Encode.object
        [ ( "path", Encode.string buildError.title )
        , ( "name", Encode.string buildError.title )
        , ( "problems"
          , Encode.list
                messagesEncoder
                [ buildError.message ]
          )
        ]


messagesEncoder : List Terminal.Text -> Encode.Value
messagesEncoder messages =
    Encode.object
        [ ( "title", Encode.string "NAMING ERROR" )
        , ( "message"
          , Encode.list Terminal.encoder messages
          )
        ]
