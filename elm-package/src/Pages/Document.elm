module Pages.Document exposing
    ( Document
    , DocumentHandler
    , markupParser
    , parser
    )

import Dict exposing (Dict)
import Html exposing (Html)
import Json.Decode
import Mark
import Mark.Error


type alias Document metadata view =
    Dict String (DocumentHandler metadata view)


type alias DocumentHandler metadata view =
    { frontmatterParser : String -> Result String metadata
    , contentParser : String -> Result String view
    }


parser :
    { extension : String
    , metadata : Json.Decode.Decoder metadata
    , body : String -> Result String view
    }
    -> ( String, DocumentHandler metadata view )
parser { extension, body, metadata } =
    ( extension
    , { contentParser = body
      , frontmatterParser =
            \frontmatter ->
                frontmatter
                    |> Json.Decode.decodeString metadata
                    |> Result.mapError Json.Decode.errorToString
      }
    )


markupParser :
    Mark.Document metadata
    -> Mark.Document view
    -> ( String, DocumentHandler metadata view )
markupParser metadataParser markBodyParser =
    ( "emu"
    , { contentParser = renderMarkup markBodyParser
      , frontmatterParser =
            \frontMatter ->
                Mark.compile metadataParser
                    frontMatter
                    |> (\outcome ->
                            case outcome of
                                Mark.Success parsedMetadata ->
                                    Ok parsedMetadata

                                Mark.Failure failure ->
                                    Err "Failure"

                                Mark.Almost failure ->
                                    Err "Almost failure"
                       )
      }
    )


renderMarkup : Mark.Document view -> String -> Result String view
renderMarkup markBodyParser markupBody =
    Mark.compile
        markBodyParser
        (markupBody |> String.trimLeft)
        |> (\outcome ->
                case outcome of
                    Mark.Success renderedView ->
                        Ok renderedView

                    Mark.Failure failures ->
                        failures
                            |> List.map Mark.Error.toString
                            |> String.join "\n"
                            |> Err

                    Mark.Almost failure ->
                        Err "TODO almost failure"
           )
