module Lcov.Decode exposing (decodeCoverageData)

import Json.Decode as Decode exposing (Decoder)
import Lcov exposing (Annotation, AnnotationType(..), ModuleCoverage)


{-| Decode the coverage data format used by elm-instrument + runtime counters.

Expects JSON of the form:

    { "modules":
        { "ModuleName":
            { "filePath": "/project/src/ModuleName.elm"
            , "annotations": [ { "type": "declaration", "name": "foo", "from": { "line": 5 }, "to": { "line": 7 } }, ... ]
            , "hits": [0, 1, 0, 2]
            }
        }
    }

-}
decodeCoverageData : Decoder (List ModuleCoverage)
decodeCoverageData =
    Decode.field "modules" (Decode.keyValuePairs moduleDecoder)
        |> Decode.map (List.map Tuple.second)


moduleDecoder : Decoder ModuleCoverage
moduleDecoder =
    Decode.map3 ModuleCoverage
        (Decode.field "filePath" Decode.string)
        (Decode.field "annotations" (Decode.list annotationDecoder))
        (Decode.field "hits" (Decode.list Decode.int))


annotationDecoder : Decoder Annotation
annotationDecoder =
    Decode.map4 Annotation
        (Decode.field "type" Decode.string |> Decode.map parseAnnotationType)
        (Decode.maybe (Decode.field "name" Decode.string))
        (Decode.at [ "from", "line" ] Decode.int)
        (Decode.at [ "to", "line" ] Decode.int)


parseAnnotationType : String -> AnnotationType
parseAnnotationType s =
    case s of
        "declaration" ->
            Declaration

        "letDeclaration" ->
            LetDeclaration

        "lambdaBody" ->
            LambdaBody

        "caseBranch" ->
            CaseBranch

        "ifElseBranch" ->
            IfElseBranch

        _ ->
            -- Unknown types treated as let declarations (generic expressions)
            LetDeclaration
