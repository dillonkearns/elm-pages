module Tui.Input exposing (State, init, update, insertText, view, viewMasked, text)

{-| Text input primitive for TUI applications.

Handles character insertion, deletion, cursor movement, and renders
with an inverse-video cursor indicator (the standard TUI convention).

    import Tui.Input as Input

    type alias Model =
        { input : Input.State }

    -- In update:
    case event.key of
        Tui.Sub.Escape -> dismissModal
        Tui.Sub.Enter -> submit (Input.text model.input)
        _ -> { model | input = Input.update event model.input }

    -- In view:
    Input.view { width = 40 } model.input

@docs State, init, update, insertText, view, viewMasked, text

-}

import Tui
import Tui.Screen
import Tui.Sub
import String.Graphemes as Graphemes


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
    State { content = str, cursorPos = Graphemes.length str }


{-| Extract the current text value.
-}
text : State -> String
text (State s) =
    s.content


{-| Insert a string at the cursor position. Useful for handling paste events —
when bracketed paste delivers a chunk of text, insert it all at once.

    case msg of
        GotPaste pastedText ->
            { model | input = Input.insertText pastedText model.input }

-}
insertText : String -> State -> State
insertText str (State s) =
    let
        -- Strip newlines for single-line input
        cleaned : String
        cleaned =
            str
                |> String.replace "\n" " "
                |> String.replace "\r" ""
    in
    State
        { content =
            Graphemes.left s.cursorPos s.content
                ++ cleaned
                ++ Graphemes.dropLeft s.cursorPos s.content
        , cursorPos = s.cursorPos + Graphemes.length cleaned
        }


{-| Handle a key event. Returns updated state.

Handles: character insertion, Backspace, Delete, Arrow Left/Right,
Home, End, Ctrl+A (home), Ctrl+E (end), Ctrl+K (kill to end),
Ctrl+U (kill to start).

Keys the input doesn't handle (Escape, Enter, Tab, etc.) return
the state unchanged. Match those keys before calling this:

    case event.key of
        Tui.Sub.Escape -> ( closeInput model, Effect.none )
        Tui.Sub.Enter -> ( submit model, Effect.none )
        _ -> ( { model | input = Input.update event model.input }, Effect.none )

-}
update : Tui.Sub.KeyEvent -> State -> State
update event (State s) =
    case event.key of
        Tui.Sub.Character char ->
            if List.member Tui.Sub.Ctrl event.modifiers then
                -- Ctrl+key shortcuts
                case char of
                    'a' ->
                        -- Ctrl+A: move to start
                        State { s | cursorPos = 0 }

                    'e' ->
                        -- Ctrl+E: move to end
                        State { s | cursorPos = Graphemes.length s.content }

                    'k' ->
                        -- Ctrl+K: kill from cursor to end
                        State { s | content = Graphemes.left s.cursorPos s.content }

                    'u' ->
                        -- Ctrl+U: kill from start to cursor
                        State
                            { content = Graphemes.dropLeft s.cursorPos s.content
                            , cursorPos = 0
                            }

                    _ ->
                        State s

            else
                -- Regular character: insert at cursor
                State
                    { content =
                        Graphemes.left s.cursorPos s.content
                            ++ String.fromChar char
                            ++ Graphemes.dropLeft s.cursorPos s.content
                    , cursorPos = s.cursorPos + 1
                    }

        Tui.Sub.Backspace ->
            if s.cursorPos > 0 then
                State
                    { content =
                        Graphemes.left (s.cursorPos - 1) s.content
                            ++ Graphemes.dropLeft s.cursorPos s.content
                    , cursorPos = s.cursorPos - 1
                    }

            else
                State s

        Tui.Sub.Delete ->
            if s.cursorPos < Graphemes.length s.content then
                State
                    { s
                        | content =
                            Graphemes.left s.cursorPos s.content
                                ++ Graphemes.dropLeft (s.cursorPos + 1) s.content
                    }

            else
                State s

        Tui.Sub.Arrow Tui.Sub.Left ->
            State { s | cursorPos = max 0 (s.cursorPos - 1) }

        Tui.Sub.Arrow Tui.Sub.Right ->
            State { s | cursorPos = min (Graphemes.length s.content) (s.cursorPos + 1) }

        Tui.Sub.Home ->
            State { s | cursorPos = 0 }

        Tui.Sub.End ->
            State { s | cursorPos = Graphemes.length s.content }

        _ ->
            State s


{-| Render the input as a Screen with an inverse-video cursor.

The `width` constrains how wide the input renders.

-}
view : { width : Int } -> State -> Tui.Screen.Screen
view { width } (State s) =
    let
        beforeCursor : String
        beforeCursor =
            Graphemes.left s.cursorPos s.content

        cursorChar : String
        cursorChar =
            case Graphemes.slice s.cursorPos (s.cursorPos + 1) s.content of
                "" ->
                    " "

                ch ->
                    ch

        afterCursor : String
        afterCursor =
            Graphemes.dropLeft (s.cursorPos + 1) s.content
    in
    renderWithCursor { width = width }
        { beforeCursor = beforeCursor
        , cursorChar = cursorChar
        , afterCursor = afterCursor
        }


{-| Render the input as a Screen with masked characters and an inverse-video
cursor.

Useful for password-style prompts where you still want users to see the cursor
position while hiding the actual text.

-}
viewMasked : { width : Int } -> State -> Tui.Screen.Screen
viewMasked { width } (State s) =
    let
        contentLength : Int
        contentLength =
            Graphemes.length s.content

        beforeCursor : String
        beforeCursor =
            String.repeat s.cursorPos "*"

        cursorChar : String
        cursorChar =
            if s.cursorPos < contentLength then
                "*"

            else
                " "

        afterCursor : String
        afterCursor =
            String.repeat (max 0 (contentLength - s.cursorPos - 1)) "*"
    in
    renderWithCursor { width = width }
        { beforeCursor = beforeCursor
        , cursorChar = cursorChar
        , afterCursor = afterCursor
        }


renderWithCursor :
    { width : Int }
    -> { beforeCursor : String, cursorChar : String, afterCursor : String }
    -> Tui.Screen.Screen
renderWithCursor { width } parts =
    if width <= 0 then
        Tui.Screen.empty

    else
        let
            tokens : List Token
            tokens =
                List.map PlainToken (Graphemes.toList parts.beforeCursor)
                    ++ [ CursorToken parts.cursorChar ]
                    ++ List.map PlainToken (Graphemes.toList parts.afterCursor)

            cursorIndex : Int
            cursorIndex =
                Graphemes.length parts.beforeCursor

            windowStart : Int
            windowStart =
                max 0 (cursorIndex - width + 1)

            visibleTokens : List Token
            visibleTokens =
                tokens
                    |> List.drop windowStart
                    |> List.take width
        in
        visibleTokens
            |> tokensToScreens
            |> Tui.Screen.concat


type Token
    = PlainToken String
    | CursorToken String


tokenToScreen : Token -> Tui.Screen.Screen
tokenToScreen token =
    case token of
        PlainToken textPart ->
            Tui.Screen.text textPart

        CursorToken textPart ->
            Tui.Screen.styled
                { fg = Nothing, bg = Nothing, attributes = [ Tui.Screen.Inverse ], hyperlink = Nothing }
                textPart


tokensToScreens : List Token -> List Tui.Screen.Screen
tokensToScreens tokens =
    -- elm-review: known-unoptimized-recursion
    case tokens of
        [] ->
            []

        PlainToken textPart :: rest ->
            let
                collectedText : List String
                collectedText =
                    collectPlainText rest

                remainingTokens : List Token
                remainingTokens =
                    dropPlainTokens rest
            in
            Tui.Screen.text (String.concat (textPart :: collectedText))
                :: tokensToScreens remainingTokens

        CursorToken textPart :: rest ->
            tokenToScreen (CursorToken textPart)
                :: tokensToScreens rest


collectPlainText : List Token -> List String
collectPlainText tokens =
    -- elm-review: known-unoptimized-recursion
    case tokens of
        PlainToken textPart :: rest ->
            textPart :: collectPlainText rest

        _ ->
            []


dropPlainTokens : List Token -> List Token
dropPlainTokens tokens =
    case tokens of
        PlainToken _ :: rest ->
            dropPlainTokens rest

        _ ->
            tokens
