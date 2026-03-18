module Tui.FuzzyMatch exposing (match, score, highlight)

{-| Fuzzy matching for TUI search and filtering.

Characters from the query must appear in order in the candidate, but
not necessarily consecutively. Case-insensitive. Higher scores for
consecutive matches, word-start matches, and exact case matches.

    FuzzyMatch.match "jde" "Json.Decode" == True
    FuzzyMatch.match "edj" "Json.Decode" == False

    FuzzyMatch.score "Dec" "Json.Decode" > FuzzyMatch.score "Jde" "Json.Decode"

    FuzzyMatch.highlight "JD" "Json.Decode"
    -- Just [ { text = "J", matched = True }
    --      , { text = "son.", matched = False }
    --      , { text = "D", matched = True }
    --      , { text = "ecode", matched = False }
    --      ]

@docs match, score, highlight

-}


{-| Check if query fuzzy-matches a candidate (case-insensitive,
characters in order).
-}
match : String -> String -> Bool
match query candidate =
    if String.isEmpty query then
        True

    else
        fuzzyMatchHelper
            (String.toLower query |> String.toList)
            (String.toLower candidate |> String.toList)


fuzzyMatchHelper : List Char -> List Char -> Bool
fuzzyMatchHelper queryChars candidateChars =
    case queryChars of
        [] ->
            True

        q :: restQuery ->
            case candidateChars of
                [] ->
                    False

                c :: restCandidate ->
                    if q == c then
                        fuzzyMatchHelper restQuery restCandidate

                    else
                        fuzzyMatchHelper queryChars restCandidate


{-| Score a fuzzy match (higher = better). Returns 0 for non-matches.

Scoring bonuses:
- Consecutive matched characters: +5 per consecutive char
- Start of word (after `.`, `/`, `-`, `_`, or start of string): +10
- Exact case match: +1

-}
score : String -> String -> Int
score query candidate =
    if not (match query candidate) then
        0

    else if String.isEmpty query then
        0

    else
        let
            queryChars : List Char
            queryChars =
                String.toList query

            candidateChars : List Char
            candidateChars =
                String.toList candidate

            positions : List Int
            positions =
                findMatchPositions
                    (List.map Char.toLower queryChars)
                    (List.map Char.toLower candidateChars)
                    0
        in
        scorePositions queryChars candidateChars positions


findMatchPositions : List Char -> List Char -> Int -> List Int
findMatchPositions queryChars candidateChars offset =
    case queryChars of
        [] ->
            []

        q :: restQuery ->
            case candidateChars of
                [] ->
                    []

                c :: restCandidate ->
                    if q == c then
                        offset :: findMatchPositions restQuery restCandidate (offset + 1)

                    else
                        findMatchPositions queryChars restCandidate (offset + 1)


scorePositions : List Char -> List Char -> List Int -> Int
scorePositions queryChars candidateChars positions =
    let
        candidateArray : List Char
        candidateArray =
            candidateChars

        isWordStart : Int -> Bool
        isWordStart pos =
            if pos == 0 then
                True

            else
                let
                    prevChar : Char
                    prevChar =
                        candidateArray
                            |> List.drop (pos - 1)
                            |> List.head
                            |> Maybe.withDefault ' '
                in
                prevChar == '.' || prevChar == '/' || prevChar == '-' || prevChar == '_' || prevChar == ' '

        isExactCase : Int -> Char -> Bool
        isExactCase pos queryChar =
            candidateArray
                |> List.drop pos
                |> List.head
                |> Maybe.map (\c -> c == queryChar)
                |> Maybe.withDefault False
    in
    List.map2
        (\pos queryChar ->
            let
                base : Int
                base =
                    1

                wordBonus : Int
                wordBonus =
                    if isWordStart pos then
                        10

                    else
                        0

                caseBonus : Int
                caseBonus =
                    if isExactCase pos queryChar then
                        1

                    else
                        0
            in
            base + wordBonus + caseBonus
        )
        positions
        queryChars
        |> List.sum
        |> (\baseScore ->
                -- Consecutive bonus
                let
                    consecutiveBonus : Int
                    consecutiveBonus =
                        positions
                            |> List.foldl
                                (\pos ( prev, bonus ) ->
                                    if prev + 1 == pos then
                                        ( pos, bonus + 5 )

                                    else
                                        ( pos, bonus )
                                )
                                ( -2, 0 )
                            |> Tuple.second
                in
                baseScore + consecutiveBonus
           )


{-| Return match with highlighted segments. Returns `Nothing` if no match.

Each segment has `text` (the substring) and `matched` (whether those
characters were part of the fuzzy match). Concatenating all segments'
text reproduces the original candidate string.

-}
highlight : String -> String -> Maybe (List { text : String, matched : Bool })
highlight query candidate =
    if not (match query candidate) then
        Nothing

    else if String.isEmpty query then
        Just [ { text = candidate, matched = False } ]

    else
        let
            queryChars : List Char
            queryChars =
                String.toList query

            candidateChars : List Char
            candidateChars =
                String.toList candidate

            positions : List Int
            positions =
                findMatchPositions
                    (List.map Char.toLower queryChars)
                    (List.map Char.toLower candidateChars)
                    0

            positionSet : List Int
            positionSet =
                positions
        in
        Just (buildHighlightSegments candidateChars positionSet 0 "" False [])


buildHighlightSegments : List Char -> List Int -> Int -> String -> Bool -> List { text : String, matched : Bool } -> List { text : String, matched : Bool }
buildHighlightSegments chars positions idx currentText currentMatched acc =
    case chars of
        [] ->
            if String.isEmpty currentText then
                List.reverse acc

            else
                List.reverse ({ text = currentText, matched = currentMatched } :: acc)

        c :: rest ->
            let
                isMatch : Bool
                isMatch =
                    List.member idx positions
            in
            if isMatch == currentMatched then
                -- Same segment type, extend
                buildHighlightSegments rest positions (idx + 1) (currentText ++ String.fromChar c) currentMatched acc

            else
                -- Different type, flush current and start new
                let
                    newAcc : List { text : String, matched : Bool }
                    newAcc =
                        if String.isEmpty currentText then
                            acc

                        else
                            { text = currentText, matched = currentMatched } :: acc
                in
                buildHighlightSegments rest positions (idx + 1) (String.fromChar c) isMatch newAcc
