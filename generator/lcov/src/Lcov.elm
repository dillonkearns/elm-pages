module Lcov exposing (Annotation, AnnotationType(..), ModuleCoverage, generate)


type alias ModuleCoverage =
    { filePath : String
    , annotations : List Annotation
    , hits : List Int
    }


type alias Annotation =
    { annotationType : AnnotationType
    , name : Maybe String
    , startLine : Int
    , endLine : Int
    }


type AnnotationType
    = Declaration
    | LetDeclaration
    | LambdaBody
    | CaseBranch
    | IfElseBranch


generate : List ModuleCoverage -> String
generate modules =
    modules
        |> List.map moduleToLcov
        |> String.join "\n"


moduleToLcov : ModuleCoverage -> String
moduleToLcov mod =
    let
        hitCounts =
            countHits mod.hits

        annotationsWithCounts =
            mod.annotations
                |> List.indexedMap
                    (\i ann ->
                        ( ann, hitCountFor i hitCounts )
                    )

        functions =
            annotationsWithCounts
                |> List.filterMap
                    (\( ann, count ) ->
                        case ann.name of
                            Just name ->
                                if ann.annotationType == Declaration then
                                    Just ( ann.startLine, name, count )

                                else
                                    Nothing

                            Nothing ->
                                Nothing
                    )

        fnLines =
            functions |> List.map (\( line, name, _ ) -> "FN:" ++ String.fromInt line ++ "," ++ name)

        fndaLines =
            functions |> List.map (\( _, name, count ) -> "FNDA:" ++ String.fromInt count ++ "," ++ name)

        fnf =
            List.length functions

        fnh =
            functions |> List.filter (\( _, _, count ) -> count > 0) |> List.length

        branches =
            annotationsWithCounts
                |> List.filterMap
                    (\( ann, count ) ->
                        if isBranch ann.annotationType then
                            Just ( ann.startLine, count )

                        else
                            Nothing
                    )

        brdaLines =
            branches
                |> List.indexedMap
                    (\i ( line, count ) ->
                        "BRDA:" ++ String.fromInt line ++ ",0," ++ String.fromInt i ++ "," ++ String.fromInt count
                    )

        brf =
            List.length branches

        brh =
            branches |> List.filter (\( _, count ) -> count > 0) |> List.length

        daLines =
            annotationsWithCounts
                |> List.map (\( ann, count ) -> "DA:" ++ String.fromInt ann.startLine ++ "," ++ String.fromInt count)

        lf =
            List.length daLines

        lh =
            annotationsWithCounts |> List.filter (\( _, count ) -> count > 0) |> List.length
    in
    String.join "\n"
        ([ "TN:"
         , "SF:" ++ mod.filePath
         ]
            ++ fnLines
            ++ fndaLines
            ++ (if fnf > 0 then
                    [ "FNF:" ++ String.fromInt fnf
                    , "FNH:" ++ String.fromInt fnh
                    ]

                else
                    []
               )
            ++ brdaLines
            ++ (if brf > 0 then
                    [ "BRF:" ++ String.fromInt brf
                    , "BRH:" ++ String.fromInt brh
                    ]

                else
                    []
               )
            ++ daLines
            ++ [ "LF:" ++ String.fromInt lf
               , "LH:" ++ String.fromInt lh
               , "end_of_record"
               , ""
               ]
        )


isBranch : AnnotationType -> Bool
isBranch t =
    case t of
        CaseBranch ->
            True

        IfElseBranch ->
            True

        _ ->
            False


{-| Count occurrences of each index in the hits list.
Returns a list of (index, count) pairs.
-}
countHits : List Int -> List ( Int, Int )
countHits hits =
    hits
        |> List.sort
        |> groupConsecutive
        |> List.map (\group -> ( Maybe.withDefault 0 (List.head group), List.length group ))


groupConsecutive : List Int -> List (List Int)
groupConsecutive list =
    case list of
        [] ->
            []

        first :: rest ->
            let
                ( group, remaining ) =
                    takeWhileEqual first rest
            in
            (first :: group) :: groupConsecutive remaining


takeWhileEqual : Int -> List Int -> ( List Int, List Int )
takeWhileEqual val list =
    case list of
        [] ->
            ( [], [] )

        x :: rest ->
            if x == val then
                let
                    ( more, remaining ) =
                        takeWhileEqual val rest
                in
                ( x :: more, remaining )

            else
                ( [], x :: rest )


hitCountFor : Int -> List ( Int, Int ) -> Int
hitCountFor index counts =
    counts
        |> List.filter (\( i, _ ) -> i == index)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault 0
