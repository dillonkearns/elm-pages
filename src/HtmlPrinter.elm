module HtmlPrinter exposing (htmlToString)

import ElmHtml.InternalTypes exposing (decodeElmHtml)
import ElmHtml.ToString exposing (FormatOptions, defaultFormatOptions, nodeToStringWithOptions)
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode


htmlToString : Html msg -> String
htmlToString viewHtml =
    case
        Decode.decodeValue
            (decodeElmHtml (\_ _ -> Decode.succeed ()))
            (asJsonView viewHtml)
    of
        Ok str ->
            nodeToStringWithOptions defaultFormatOptions str

        Err err ->
            "Error: " ++ Decode.errorToString err


asJsonView : Html msg -> Decode.Value
asJsonView x =
    Json.Encode.string "REPLACE_ME_WITH_JSON_STRINGIFY"
