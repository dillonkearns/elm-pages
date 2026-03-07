module Test.GlobMatch exposing
    ( MatchOptions
    , Token(..)
    , directoriesFromFiles
    , matchPaths
    , matchSinglePath
    , parsePattern
    )

{-| Pure Elm glob pattern matching for the virtual filesystem in `Test.BackendTask`.

Supports the subset of glob syntax used by `BackendTask.Glob`:

  - `*` — matches any characters except `/`
  - `**` — matches any characters including `/` (recursive wildcard)
  - `{a,b,c}` — brace expansion (alternation)
  - `[...]` — character classes (e.g. `[0-9]`)
  - `(...)` — capture groups (e.g. `([0-9]+)` from `Glob.digits`)
  - Literal strings

-}

import Set exposing (Set)


{-| A parsed glob token.
-}
type Token
    = Literal String
    | Star
    | DoubleStar
    | DoubleStarSlash
    | BraceGroup (List String)
    | CharClass (List CharRange)
    | CharClassNegated (List CharRange)
    | ParenCapture (List CharRange) ParenQuantifier


type CharRange
    = Single Char
    | Range Char Char


type ParenQuantifier
    = OneOrMore
    | ZeroOrMore_
    | ZeroOrOne_



-- PARSING


{-| Parse a glob pattern string into a list of tokens.
-}
parsePattern : String -> List Token
parsePattern pattern =
    parseHelp (String.toList pattern) [] []
        |> List.reverse
        |> mergeAdjacentLiterals


parseHelp : List Char -> List Char -> List Token -> List Token
parseHelp chars currentLiteral tokens =
    case chars of
        [] ->
            finishLiteral currentLiteral tokens

        '*' :: '*' :: '/' :: rest ->
            parseHelp rest [] (DoubleStarSlash :: finishLiteral currentLiteral tokens)

        '*' :: '*' :: rest ->
            parseHelp rest [] (DoubleStar :: finishLiteral currentLiteral tokens)

        '*' :: rest ->
            parseHelp rest [] (Star :: finishLiteral currentLiteral tokens)

        '{' :: rest ->
            let
                ( alternatives, remaining ) =
                    parseBraceGroup rest
            in
            parseHelp remaining [] (BraceGroup alternatives :: finishLiteral currentLiteral tokens)

        '(' :: rest ->
            let
                ( ranges, remaining ) =
                    parseParenCapture rest
            in
            case remaining of
                '+' :: afterQuantifier ->
                    parseHelp afterQuantifier [] (ParenCapture ranges OneOrMore :: finishLiteral currentLiteral tokens)

                '*' :: afterQuantifier ->
                    parseHelp afterQuantifier [] (ParenCapture ranges ZeroOrMore_ :: finishLiteral currentLiteral tokens)

                '?' :: afterQuantifier ->
                    parseHelp afterQuantifier [] (ParenCapture ranges ZeroOrOne_ :: finishLiteral currentLiteral tokens)

                _ ->
                    -- Default: one or more (used by digits pattern `([0-9]+)`)
                    parseHelp remaining [] (ParenCapture ranges OneOrMore :: finishLiteral currentLiteral tokens)

        '[' :: rest ->
            let
                ( ranges, negated, remaining ) =
                    parseCharClass rest
            in
            if negated then
                parseHelp remaining [] (CharClassNegated ranges :: finishLiteral currentLiteral tokens)

            else
                parseHelp remaining [] (CharClass ranges :: finishLiteral currentLiteral tokens)

        '?' :: rest ->
            -- ? in glob matches exactly one character (except /)
            -- We'll treat it as a character class that matches any non-slash
            parseHelp rest [] (CharClass [ Range '\u{0001}' '.', Range '0' '\u{FFFF}' ] :: finishLiteral currentLiteral tokens)

        c :: rest ->
            parseHelp rest (c :: currentLiteral) tokens


finishLiteral : List Char -> List Token -> List Token
finishLiteral chars tokens =
    case chars of
        [] ->
            tokens

        _ ->
            Literal (String.fromList (List.reverse chars)) :: tokens


{-| Merge adjacent Literal tokens into one.
-}
mergeAdjacentLiterals : List Token -> List Token
mergeAdjacentLiterals tokens =
    case tokens of
        [] ->
            []

        (Literal a) :: (Literal b) :: rest ->
            mergeAdjacentLiterals (Literal (a ++ b) :: rest)

        t :: rest ->
            t :: mergeAdjacentLiterals rest


parseBraceGroup : List Char -> ( List String, List Char )
parseBraceGroup chars =
    parseBraceGroupHelp chars [] []


parseBraceGroupHelp : List Char -> List Char -> List String -> ( List String, List Char )
parseBraceGroupHelp chars current alternatives =
    case chars of
        [] ->
            -- Unterminated brace group — treat as literal
            ( List.reverse (String.fromList (List.reverse current) :: alternatives), [] )

        '}' :: rest ->
            ( List.reverse (String.fromList (List.reverse current) :: alternatives), rest )

        ',' :: rest ->
            parseBraceGroupHelp rest [] (String.fromList (List.reverse current) :: alternatives)

        c :: rest ->
            parseBraceGroupHelp rest (c :: current) alternatives


parseCharClass : List Char -> ( List CharRange, Bool, List Char )
parseCharClass chars =
    case chars of
        '!' :: rest ->
            let
                ( ranges, remaining ) =
                    parseCharClassRanges rest
            in
            ( ranges, True, remaining )

        '^' :: rest ->
            let
                ( ranges, remaining ) =
                    parseCharClassRanges rest
            in
            ( ranges, True, remaining )

        _ ->
            let
                ( ranges, remaining ) =
                    parseCharClassRanges chars
            in
            ( ranges, False, remaining )


parseCharClassRanges : List Char -> ( List CharRange, List Char )
parseCharClassRanges chars =
    parseCharClassRangesHelp chars []


parseCharClassRangesHelp : List Char -> List CharRange -> ( List CharRange, List Char )
parseCharClassRangesHelp chars ranges =
    case chars of
        [] ->
            ( List.reverse ranges, [] )

        ']' :: rest ->
            ( List.reverse ranges, rest )

        c :: '-' :: d :: rest ->
            if d /= ']' then
                parseCharClassRangesHelp rest (Range c d :: ranges)

            else
                -- c followed by literal '-' at end
                parseCharClassRangesHelp (d :: rest) (Single '-' :: Single c :: ranges)

        c :: rest ->
            parseCharClassRangesHelp rest (Single c :: ranges)


parseParenCapture : List Char -> ( List CharRange, List Char )
parseParenCapture chars =
    -- Parse content inside (...) — supports character class syntax like [0-9]
    parseParenCaptureHelp chars []


parseParenCaptureHelp : List Char -> List CharRange -> ( List CharRange, List Char )
parseParenCaptureHelp chars ranges =
    case chars of
        [] ->
            ( List.reverse ranges, [] )

        ')' :: rest ->
            ( List.reverse ranges, rest )

        '[' :: rest ->
            let
                ( classRanges, _, remaining ) =
                    parseCharClass rest
            in
            parseParenCaptureHelp remaining (List.reverse classRanges ++ ranges)

        c :: rest ->
            parseParenCaptureHelp rest (Single c :: ranges)



-- MATCHING


type alias MatchOptions =
    { caseSensitive : Bool
    , dot : Bool
    }


{-| Match a list of file paths against a parsed token list.
Returns matches with their captured groups.
-}
matchPaths :
    MatchOptions
    -> List Token
    -> List String
    -> List { fullPath : String, captures : List String }
matchPaths options tokens paths =
    paths
        |> List.filterMap
            (\path ->
                matchSinglePath options tokens path
                    |> Maybe.map (\captures -> { fullPath = path, captures = captures })
            )


{-| Match a single path against a parsed token list.
Returns Just with captures on success, Nothing on failure.
-}
matchSinglePath : MatchOptions -> List Token -> String -> Maybe (List String)
matchSinglePath options tokens path =
    matchTokens options tokens path


matchTokens : MatchOptions -> List Token -> String -> Maybe (List String)
matchTokens options tokens remaining =
    case tokens of
        [] ->
            if remaining == "" then
                Just []

            else
                Nothing

        (Literal s) :: rest ->
            if options.caseSensitive then
                if String.startsWith s remaining then
                    matchTokens options rest (String.dropLeft (String.length s) remaining)

                else
                    Nothing

            else if String.startsWith (String.toLower s) (String.toLower remaining) then
                matchTokens options rest (String.dropLeft (String.length s) remaining)

            else
                Nothing

        Star :: rest ->
            tryStarMatch options rest remaining 0

        DoubleStar :: rest ->
            tryDoubleStarMatch options rest remaining 0

        DoubleStarSlash :: rest ->
            tryDoubleStarSlashMatch options rest remaining ""

        (BraceGroup alternatives) :: rest ->
            tryBraceMatch options alternatives rest remaining

        (CharClass ranges) :: rest ->
            tryCharClassMatch options ranges False rest remaining 0

        (CharClassNegated ranges) :: rest ->
            tryCharClassMatch options ranges True rest remaining 0

        (ParenCapture ranges quantifier) :: rest ->
            tryParenCaptureMatch options ranges quantifier rest remaining


{-| Try matching `*` — consumes 0 or more non-`/` characters.
-}
tryStarMatch : MatchOptions -> List Token -> String -> Int -> Maybe (List String)
tryStarMatch options rest path n =
    if n > String.length path then
        Nothing

    else
        let
            prefix =
                String.left n path
        in
        if String.contains "/" prefix then
            Nothing

        else if n > 0 && not options.dot && String.startsWith "." prefix then
            -- Don't match dot files/segments with * unless dot=true
            Nothing

        else
            case matchTokens options rest (String.dropLeft n path) of
                Just captures ->
                    Just (prefix :: captures)

                Nothing ->
                    tryStarMatch options rest path (n + 1)


{-| Try matching `**` at end of pattern or before non-slash token.
-}
tryDoubleStarMatch : MatchOptions -> List Token -> String -> Int -> Maybe (List String)
tryDoubleStarMatch options rest path n =
    if n > String.length path then
        Nothing

    else
        let
            prefix =
                String.left n path
        in
        if n > 0 && not options.dot && containsDotSegment prefix then
            tryDoubleStarMatch options rest path (n + 1)

        else
            case matchTokens options rest (String.dropLeft n path) of
                Just captures ->
                    Just (prefix :: captures)

                Nothing ->
                    tryDoubleStarMatch options rest path (n + 1)


{-| Try matching `**/` — zero or more complete directory segments.
-}
tryDoubleStarSlashMatch : MatchOptions -> List Token -> String -> String -> Maybe (List String)
tryDoubleStarSlashMatch options rest path accumulated =
    -- Try matching with current accumulated segments
    case matchTokens options rest path of
        Just captures ->
            Just (accumulated :: captures)

        Nothing ->
            -- Try consuming one more directory segment
            case findNextSlash path of
                Just ( segment, remaining ) ->
                    if not options.dot && String.startsWith "." segment then
                        -- Skip dot segments when dot=false
                        Nothing

                    else
                        let
                            newAccumulated =
                                if accumulated == "" then
                                    segment

                                else
                                    accumulated ++ "/" ++ segment
                        in
                        tryDoubleStarSlashMatch options rest remaining newAccumulated

                Nothing ->
                    Nothing


{-| Try matching `{a,b,c}` — one of the alternatives.
-}
tryBraceMatch : MatchOptions -> List String -> List Token -> String -> Maybe (List String)
tryBraceMatch options alternatives rest remaining =
    case alternatives of
        [] ->
            Nothing

        alt :: others ->
            let
                matches =
                    if options.caseSensitive then
                        String.startsWith alt remaining

                    else
                        String.startsWith (String.toLower alt) (String.toLower remaining)
            in
            if matches then
                case matchTokens options rest (String.dropLeft (String.length alt) remaining) of
                    Just captures ->
                        Just (alt :: captures)

                    Nothing ->
                        tryBraceMatch options others rest remaining

            else
                tryBraceMatch options others rest remaining


{-| Try matching a character class — `[0-9]`, `[a-z]`, etc.
Matches exactly one character.
-}
tryCharClassMatch : MatchOptions -> List CharRange -> Bool -> List Token -> String -> Int -> Maybe (List String)
tryCharClassMatch options ranges negated rest path n =
    if n >= 1 then
        -- Character classes match exactly one character
        let
            c =
                String.left 1 path
        in
        if c == "" || c == "/" then
            Nothing

        else
            let
                charMatches =
                    charInRanges ranges (String.uncons c |> Maybe.map Tuple.first |> Maybe.withDefault ' ')

                actualMatch =
                    if negated then
                        not charMatches

                    else
                        charMatches
            in
            if actualMatch then
                case matchTokens options rest (String.dropLeft 1 path) of
                    Just captures ->
                        Just (c :: captures)

                    Nothing ->
                        Nothing

            else
                Nothing

    else
        -- Start: try matching one character
        tryCharClassMatch options ranges negated rest path 1


{-| Try matching a parenthesized capture group with quantifier.
Used for patterns like `([0-9]+)`.
-}
tryParenCaptureMatch : MatchOptions -> List CharRange -> ParenQuantifier -> List Token -> String -> Maybe (List String)
tryParenCaptureMatch options ranges quantifier rest remaining =
    let
        minCount =
            case quantifier of
                OneOrMore ->
                    1

                ZeroOrMore_ ->
                    0

                ZeroOrOne_ ->
                    0

        maxCount =
            case quantifier of
                ZeroOrOne_ ->
                    1

                _ ->
                    String.length remaining
    in
    tryParenCaptureMatchHelp options ranges rest remaining minCount maxCount


tryParenCaptureMatchHelp : MatchOptions -> List CharRange -> List Token -> String -> Int -> Int -> Maybe (List String)
tryParenCaptureMatchHelp options ranges rest remaining minCount maxCount =
    -- Try consuming `minCount` to `maxCount` matching characters
    let
        maxPossible =
            countMatchingChars ranges remaining 0
    in
    -- Try from longest to shortest (greedy)
    tryParenCaptureMatchN options ranges rest remaining (min maxPossible maxCount) minCount


tryParenCaptureMatchN : MatchOptions -> List CharRange -> List Token -> String -> Int -> Int -> Maybe (List String)
tryParenCaptureMatchN options ranges rest remaining n minN =
    if n < minN then
        Nothing

    else
        let
            prefix =
                String.left n remaining
        in
        case matchTokens options rest (String.dropLeft n remaining) of
            Just captures ->
                Just (prefix :: captures)

            Nothing ->
                tryParenCaptureMatchN options ranges rest remaining (n - 1) minN


countMatchingChars : List CharRange -> String -> Int -> Int
countMatchingChars ranges str count =
    case String.uncons str of
        Just ( c, rest ) ->
            if charInRanges ranges c then
                countMatchingChars ranges rest (count + 1)

            else
                count

        Nothing ->
            count



-- HELPERS


charInRanges : List CharRange -> Char -> Bool
charInRanges ranges c =
    List.any (charInRange c) ranges


charInRange : Char -> CharRange -> Bool
charInRange c range =
    case range of
        Single target ->
            c == target

        Range lo hi ->
            Char.toCode c >= Char.toCode lo && Char.toCode c <= Char.toCode hi


findNextSlash : String -> Maybe ( String, String )
findNextSlash path =
    let
        chars =
            String.toList path
    in
    findNextSlashHelp chars []


findNextSlashHelp : List Char -> List Char -> Maybe ( String, String )
findNextSlashHelp chars acc =
    case chars of
        [] ->
            Nothing

        '/' :: rest ->
            Just ( String.fromList (List.reverse acc), String.fromList rest )

        c :: rest ->
            findNextSlashHelp rest (c :: acc)


{-| Check if a path string contains a segment starting with `.`
Used for dot file filtering.
-}
containsDotSegment : String -> Bool
containsDotSegment path =
    if String.startsWith "." path then
        True

    else
        String.contains "/." path


{-| Get all unique parent directories from a list of file paths.
Used to support `onlyDirectories` glob option.

    directoriesFromFiles [ "a/b/c.txt", "a/d.txt" ]
    --> Set.fromList [ "a", "a/b" ]

-}
directoriesFromFiles : List String -> Set String
directoriesFromFiles paths =
    paths
        |> List.concatMap parentDirs
        |> Set.fromList


parentDirs : String -> List String
parentDirs path =
    path
        |> String.split "/"
        |> List.reverse
        |> List.drop 1
        |> List.reverse
        |> buildDirPaths [] ""


buildDirPaths : List String -> String -> List String -> List String
buildDirPaths acc prefix parts =
    case parts of
        [] ->
            acc

        part :: rest ->
            let
                dir =
                    if prefix == "" then
                        part

                    else
                        prefix ++ "/" ++ part
            in
            buildDirPaths (dir :: acc) dir rest
