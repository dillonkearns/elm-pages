module Pattern exposing (Pattern(..), Segment(..), State(..), addCapture, addLiteral, addSlash, empty, toJson)

import Json.Encode


toJson : Pattern -> Json.Encode.Value
toJson (Pattern segments _) =
    Json.Encode.list segmentToJson segments


segmentToJson : Segment -> Json.Encode.Value
segmentToJson segment =
    -- elm-review: known-unoptimized-recursion
    case segment of
        Literal literalString ->
            Json.Encode.object
                [ ( "kind", Json.Encode.string "literal" )
                , ( "value", Json.Encode.string literalString )
                ]

        Dynamic ->
            Json.Encode.object
                [ ( "kind", Json.Encode.string "dynamic" )
                ]

        HybridSegment ( first, second, rest ) ->
            Json.Encode.object
                [ ( "kind", Json.Encode.string "hybrid" )
                , ( "value", Json.Encode.list segmentToJson (first :: second :: rest) )
                ]


empty : Pattern
empty =
    Pattern [] NoPendingSlash


addSlash : Pattern -> Pattern
addSlash (Pattern segments _) =
    Pattern segments PendingSlash


addCapture : Pattern -> Pattern
addCapture (Pattern segments state) =
    case state of
        PendingSlash ->
            Pattern (segments ++ [ Dynamic ]) NoPendingSlash

        NoPendingSlash ->
            case segments |> List.reverse of
                [] ->
                    Pattern [ Dynamic ] NoPendingSlash

                last :: rest ->
                    Pattern (List.reverse rest ++ [ HybridSegment ( last, Dynamic, [] ) ]) NoPendingSlash


addLiteral : String -> Pattern -> Pattern
addLiteral newLiteral (Pattern segments state) =
    case state of
        PendingSlash ->
            Pattern
                (segments ++ [ Literal newLiteral ])
                NoPendingSlash

        NoPendingSlash ->
            case segments |> List.reverse of
                (Literal literalSegment) :: rest ->
                    Pattern
                        (List.reverse rest ++ [ Literal (literalSegment ++ newLiteral) ])
                        NoPendingSlash

                last :: rest ->
                    Pattern (List.reverse rest ++ [ HybridSegment ( last, Literal newLiteral, [] ) ]) NoPendingSlash

                _ ->
                    Pattern
                        (segments ++ [ Literal newLiteral ])
                        state



--Pattern segments state


type Pattern
    = Pattern (List Segment) State


type State
    = PendingSlash
    | NoPendingSlash


type Segment
    = Literal String
    | Dynamic
    | HybridSegment ( Segment, Segment, List Segment )
