module BuildError exposing (BuildError, encode, errorToString, errorsToString, internal)

import Json.Encode as Encode
import TerminalText as Terminal


type alias BuildError =
    { title : String
    , path : String
    , message : List Terminal.Text
    , fatal : Bool
    }


internal : String -> { title : String, path : String, message : List Terminal.Text, fatal : Bool }
internal string =
    { title = "Internal Error"
    , path = ""
    , message = [ Terminal.text string ]
    , fatal = True
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
        ("-- " ++ String.toUpper title ++ " ----------------------------------------------------- elm-pages")
    , Terminal.text "\n\n"
    ]


encode : List BuildError -> Encode.Value
encode buildErrors =
    Encode.object
        [ ( "type", Encode.string "compile-errors" )
        , ( "errors"
          , Encode.list
                (\buildError ->
                    Encode.object
                        [ ( "path", Encode.string buildError.path )
                        , ( "name", Encode.string buildError.title )
                        , ( "problems", Encode.list (messagesEncoder buildError.title) [ buildError.message ] )
                        ]
                )
                buildErrors
          )
        ]


messagesEncoder : String -> List Terminal.Text -> Encode.Value
messagesEncoder title messages =
    Encode.object
        [ ( "title", Encode.string title )
        , ( "message", Encode.list Terminal.encoder messages )
        ]
