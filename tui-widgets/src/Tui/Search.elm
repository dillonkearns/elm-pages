module Tui.Search exposing
    ( State, start
    , typeChar, backspace
    , nextMatch, prevMatch
    , query, matchCount, currentMatch, matchLineIndex
    , statusText
    )

{-| In-pane text search with match navigation.

Activate with `/`, type to search, `n`/`N` to navigate between matches,
`Escape` to cancel. Smart-case: case-insensitive unless the query
contains uppercase characters (like vim/lazygit).

    -- In model:
    { search : Maybe Search.State }

    -- On `/` key:
    { model | search = Just Search.start }

    -- While searching, handle keys:
    Tui.Character c -> { model | search = Maybe.map (Search.typeChar c) model.search }
    Tui.Backspace -> { model | search = Maybe.map Search.backspace model.search }
    Tui.Character 'n' -> { model | search = Maybe.map (Search.nextMatch content) model.search }
    Tui.Character 'N' -> { model | search = Maybe.map (Search.prevMatch content) model.search }
    Tui.Escape -> { model | search = Nothing }

    -- Get the scroll offset to center on current match:
    Search.matchLineIndex content searchState

@docs State, start
@docs typeChar, backspace
@docs nextMatch, prevMatch
@docs query, matchCount, currentMatch, matchLineIndex
@docs statusText

-}

import Tui


{-| Opaque search state.
-}
type State
    = State
        { queryText : String
        , matchIndex : Int
        }


{-| Start a new search session.
-}
start : State
start =
    State { queryText = "", matchIndex = 0 }


{-| Type a character into the search query.
-}
typeChar : Char -> State -> State
typeChar c (State s) =
    State { s | queryText = s.queryText ++ String.fromChar c, matchIndex = 0 }


{-| Delete the last character from the search query.
-}
backspace : State -> State
backspace (State s) =
    State { s | queryText = String.dropRight 1 s.queryText, matchIndex = 0 }


{-| Move to the next match (wraps around).
-}
nextMatch : List Tui.Screen -> State -> State
nextMatch content (State s) =
    let
        count =
            findMatchLines s.queryText content |> List.length
    in
    if count == 0 then
        State s

    else
        State { s | matchIndex = modBy count (s.matchIndex + 1) }


{-| Move to the previous match (wraps around).
-}
prevMatch : List Tui.Screen -> State -> State
prevMatch content (State s) =
    let
        count =
            findMatchLines s.queryText content |> List.length
    in
    if count == 0 then
        State s

    else
        State { s | matchIndex = modBy count (s.matchIndex - 1 + count) }


{-| Get the current search query text.
-}
query : State -> String
query (State s) =
    s.queryText



{-| How many lines match the current query?
-}
matchCount : List Tui.Screen -> State -> Int
matchCount content (State s) =
    if String.isEmpty s.queryText then
        0

    else
        findMatchLines s.queryText content |> List.length


{-| The current match index (0-based).
-}
currentMatch : State -> Int
currentMatch (State s) =
    s.matchIndex


{-| Get the line index of the current match. Use this to scroll the
pane to the match position. Returns `Nothing` when there are no matches.
-}
matchLineIndex : List Tui.Screen -> State -> Maybe Int
matchLineIndex content (State s) =
    let
        matchLines =
            findMatchLines s.queryText content
    in
    matchLines
        |> List.drop s.matchIndex
        |> List.head


{-| Status text like "1/3" or "no matches for 'foo'".
-}
statusText : List Tui.Screen -> State -> String
statusText content (State s) =
    if String.isEmpty s.queryText then
        ""

    else
        let
            matches =
                findMatchLines s.queryText content
            count =
                List.length matches
        in
        if count == 0 then
            "no matches for '" ++ s.queryText ++ "'"

        else
            String.fromInt (s.matchIndex + 1) ++ "/" ++ String.fromInt count



-- INTERNAL


{-| Find line indices that contain the query. Smart-case: case-insensitive
unless query contains uppercase characters.
-}
findMatchLines : String -> List Tui.Screen -> List Int
findMatchLines queryText content =
    if String.isEmpty queryText then
        []

    else
        let
            caseSensitive : Bool
            caseSensitive =
                String.any Char.isUpper queryText

            normalizedQuery : String
            normalizedQuery =
                if caseSensitive then
                    queryText

                else
                    String.toLower queryText
        in
        content
            |> List.indexedMap
                (\i screen ->
                    let
                        lineText : String
                        lineText =
                            Tui.toString screen

                        normalizedLine : String
                        normalizedLine =
                            if caseSensitive then
                                lineText

                            else
                                String.toLower lineText
                    in
                    if String.contains normalizedQuery normalizedLine then
                        Just i

                    else
                        Nothing
                )
            |> List.filterMap identity
