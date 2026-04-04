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
                        ( extendCaseBranchToPatternLine ann, hitCountFor i hitCounts )
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

        -- Expand each annotation to cover its full line range.
        -- When annotations overlap, the innermost (smallest range) wins,
        -- so an unhit branch correctly shows 0 even inside a hit declaration.
        lineCounts =
            let
                allLines =
                    annotationsWithCounts
                        |> List.concatMap
                            (\( ann, _ ) -> List.range ann.startLine ann.endLine)
                        |> List.sort
                        |> unique
            in
            allLines
                |> List.map
                    (\line ->
                        ( line, innermostCount line annotationsWithCounts )
                    )

        daLines =
            lineCounts
                |> List.map (\( line, count ) -> "DA:" ++ String.fromInt line ++ "," ++ String.fromInt count)

        lf =
            List.length daLines

        lh =
            lineCounts |> List.filter (\( _, count ) -> count > 0) |> List.length
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


{-| For a given line, find the innermost annotation that covers it
(smallest range) and return its hit count.
-}
innermostCount : Int -> List ( Annotation, Int ) -> Int
innermostCount line anns =
    anns
        |> List.filter (\( ann, _ ) -> ann.startLine <= line && line <= ann.endLine)
        |> List.sortBy (\( ann, _ ) -> ann.endLine - ann.startLine)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault 0


unique : List Int -> List Int
unique list =
    case list of
        [] ->
            []

        [ x ] ->
            [ x ]

        x :: y :: rest ->
            if x == y then
                unique (y :: rest)

            else
                x :: unique (y :: rest)


{-| Case patterns are declarative — "Decrement ->" doesn't execute code,
it's a structural description. The pattern line belongs to the branch.
If/else conditions ARE code that runs, so we don't extend those.
-}
extendCaseBranchToPatternLine : Annotation -> Annotation
extendCaseBranchToPatternLine ann =
    if ann.annotationType == CaseBranch && ann.startLine > 1 then
        { ann | startLine = ann.startLine - 1 }

    else
        ann


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
