module Tui.Input exposing (State, init, update, view, text)

{-| Text input primitive for TUI applications.

Handles character insertion, deletion, cursor movement, and renders
with an inverse-video cursor indicator (the standard TUI convention).

    import Tui.Input as Input

    type alias Model =
        { input : Input.State }

    -- In update:
    case event.key of
        Tui.Escape -> dismissModal
        Tui.Enter -> submit (Input.text model.input)
        _ -> { model | input = Input.update event model.input }

    -- In view:
    Input.view { width = 40 } model.input

@docs State, init, update, view, text

-}

import Tui


{-| Opaque state for a text input. Tracks content and cursor position.
-}
type State
    = State
        { content : String
        , cursorPos : Int
        }


{-| Create an input with initial text. Cursor starts at the end.
-}
init : String -> State
init str =
    State { content = str, cursorPos = String.length str }


{-| Extract the current text value.
-}
text : State -> String
text (State s) =
    s.content


{-| Handle a key event. Returns updated state.

Handles: character insertion, Backspace, Delete, Arrow Left/Right,
Home, End, Ctrl+A (home), Ctrl+E (end), Ctrl+K (kill to end),
Ctrl+U (kill to start).

Keys the input doesn't care about (Escape, Enter, Tab, etc.) return
the state unchanged — check for those in your update function FIRST.

-}
update : Tui.KeyEvent -> State -> State
update event (State s) =
    case event.key of
        Tui.Character char ->
            if List.member Tui.Ctrl event.modifiers then
                -- Ctrl+key shortcuts
                case char of
                    'a' ->
                        -- Ctrl+A: move to start
                        State { s | cursorPos = 0 }

                    'e' ->
                        -- Ctrl+E: move to end
                        State { s | cursorPos = String.length s.content }

                    'k' ->
                        -- Ctrl+K: kill from cursor to end
                        State { s | content = String.left s.cursorPos s.content }

                    'u' ->
                        -- Ctrl+U: kill from start to cursor
                        State
                            { content = String.dropLeft s.cursorPos s.content
                            , cursorPos = 0
                            }

                    _ ->
                        State s

            else
                -- Regular character: insert at cursor
                State
                    { content =
                        String.left s.cursorPos s.content
                            ++ String.fromChar char
                            ++ String.dropLeft s.cursorPos s.content
                    , cursorPos = s.cursorPos + 1
                    }

        Tui.Backspace ->
            if s.cursorPos > 0 then
                State
                    { content =
                        String.left (s.cursorPos - 1) s.content
                            ++ String.dropLeft s.cursorPos s.content
                    , cursorPos = s.cursorPos - 1
                    }

            else
                State s

        Tui.Delete ->
            if s.cursorPos < String.length s.content then
                State
                    { s
                        | content =
                            String.left s.cursorPos s.content
                                ++ String.dropLeft (s.cursorPos + 1) s.content
                    }

            else
                State s

        Tui.Arrow Tui.Left ->
            State { s | cursorPos = max 0 (s.cursorPos - 1) }

        Tui.Arrow Tui.Right ->
            State { s | cursorPos = min (String.length s.content) (s.cursorPos + 1) }

        Tui.Home ->
            State { s | cursorPos = 0 }

        Tui.End ->
            State { s | cursorPos = String.length s.content }

        _ ->
            State s


{-| Render the input as a Screen with an inverse-video cursor.

The `width` constrains how wide the input renders.

-}
view : { width : Int } -> State -> Tui.Screen
view { width } (State s) =
    let
        beforeCursor : String
        beforeCursor =
            String.left s.cursorPos s.content

        cursorChar : String
        cursorChar =
            case String.slice s.cursorPos (s.cursorPos + 1) s.content of
                "" ->
                    " "

                ch ->
                    ch

        afterCursor : String
        afterCursor =
            String.dropLeft (s.cursorPos + 1) s.content
    in
    Tui.concat
        [ Tui.text beforeCursor
        , Tui.styled
            { fg = Nothing, bg = Nothing, attributes = [ Tui.inverse ] }
            cursorChar
        , Tui.text afterCursor
        ]
        |> Tui.truncateWidth width
