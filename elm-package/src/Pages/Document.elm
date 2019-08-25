module Pages.Document exposing
    ( Document
    , DocumentParser
    , markupParser
    , parseContent
    , parseMetadata
    , parser
    )

import Dict exposing (Dict)
import Html exposing (Html)
import Json.Decode
import Mark
import Mark.Error


type alias Document metadata view =
    Dict String
        { frontmatterParser : String -> Result String metadata
        , contentParser : String -> Result String view
        }


type alias DocumentParser metadata view =
    ( String
    , { frontmatterParser : String -> Result String metadata
      , contentParser : String -> Result String view
      }
    )


parser :
    { extension : String
    , metadata : Json.Decode.Decoder metadata
    , body : String -> Result String view
    }
    -> DocumentParser metadata view
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
    -> DocumentParser metadata view
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


parseMetadata :
    Document metadata view
    -> List ( List String, { extension : String, frontMatter : String, body : Maybe String } )
    -> List ( List String, Result String { extension : String, metadata : metadata } )
parseMetadata document content =
    content
        |> List.map
            (Tuple.mapSecond
                (\{ frontMatter, extension } ->
                    let
                        maybeDocumentEntry =
                            Dict.get extension document
                    in
                    case maybeDocumentEntry of
                        Just documentEntry ->
                            frontMatter
                                |> documentEntry.frontmatterParser
                                |> Result.map
                                    (\metadata ->
                                        { metadata = metadata
                                        , extension = extension
                                        }
                                    )

                        Nothing ->
                            Err ("Could not find extension '" ++ extension ++ "'")
                )
            )


parseContent :
    String
    -> String
    -> Document metadata view
    -> Result String view
parseContent extension body document =
    let
        maybeDocumentEntry =
            Dict.get extension document
    in
    case maybeDocumentEntry of
        Just documentEntry ->
            documentEntry.contentParser body

        Nothing ->
            Err ("Could not find extension '" ++ extension ++ "'")
