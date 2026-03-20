module Tui.Confirm exposing
    ( State
    , confirm, prompt
    , typeChar, backspace, handleKeyEvent
    , title, viewBody, viewFooter, inputText, isPrompt
    )

{-| Confirmation dialogs and text prompts.

Inspired by lazygit's `Confirm` and `Prompt` APIs. Two modes:
- **Confirm**: Yes/No with a message. Enter confirms, Escape cancels.
- **Prompt**: Text input with title. Enter submits text, Escape cancels.

    -- Confirmation:
    model.dialog = Just (Confirm.confirm { title = "Delete?", message = "Cannot undo." })

    -- Prompt:
    model.dialog = Just (Confirm.prompt { title = "Branch name", initialValue = "feature/" })

    -- In update while dialog is active:
    Tui.Enter ->
        case model.dialog of
            Just state ->
                if Confirm.isPrompt state then
                    handleSubmit (Confirm.inputText state)
                else
                    handleConfirm
            Nothing -> ...
    Tui.Escape -> { model | dialog = Nothing }

    -- Render with Modal.overlay:
    Modal.overlay
        { title = Confirm.title state
        , body = Confirm.viewBody state
        , footer = Confirm.viewFooter state
        , width = 50
        }
        { width = ctx.width, height = ctx.height } bgRows

@docs State
@docs confirm, prompt
@docs typeChar, backspace, handleKeyEvent
@docs title, viewBody, viewFooter, inputText, isPrompt

-}

import Tui
import Tui.Input as Input


{-| Opaque dialog state — either a confirmation or a prompt.
-}
type State
    = ConfirmState
        { dialogTitle : String
        , message : String
        }
    | PromptState
        { dialogTitle : String
        , input : Input.State
        }


{-| Create a Yes/No confirmation dialog.
-}
confirm : { title : String, message : String } -> State
confirm config =
    ConfirmState
        { dialogTitle = config.title
        , message = config.message
        }


{-| Create a text input prompt.
-}
prompt : { title : String, initialValue : String } -> State
prompt config =
    PromptState
        { dialogTitle = config.title
        , input = Input.init config.initialValue
        }


{-| Type a character (only affects prompts, no-op on confirmations).
-}
typeChar : Char -> State -> State
typeChar c state =
    case state of
        PromptState s ->
            PromptState { s | input = Input.update { key = Tui.Character c, modifiers = [] } s.input }

        ConfirmState _ ->
            state


{-| Delete last character (only affects prompts).
-}
backspace : State -> State
backspace state =
    case state of
        PromptState s ->
            PromptState { s | input = Input.update { key = Tui.Backspace, modifiers = [] } s.input }

        ConfirmState _ ->
            state


{-| Pass a full key event to the dialog (routes to Input.update for prompts).
-}
handleKeyEvent : Tui.KeyEvent -> State -> State
handleKeyEvent event state =
    case state of
        PromptState s ->
            PromptState { s | input = Input.update event s.input }

        ConfirmState _ ->
            state


{-| Get the dialog title.
-}
title : State -> String
title state =
    case state of
        ConfirmState s ->
            s.dialogTitle

        PromptState s ->
            s.dialogTitle


{-| Render the dialog body.
-}
viewBody : State -> List Tui.Screen
viewBody state =
    case state of
        ConfirmState s ->
            [ Tui.blank
            , Tui.text ("  " ++ s.message)
            , Tui.blank
            ]

        PromptState s ->
            [ Tui.blank
            , Input.view { width = 40 } s.input
            , Tui.blank
            ]


{-| Render footer hint text.
-}
viewFooter : State -> String
viewFooter state =
    case state of
        ConfirmState _ ->
            "Enter: confirm │ Esc: cancel"

        PromptState _ ->
            "Enter: submit │ Esc: cancel"


{-| Get the current input text (prompts only, returns "" for confirmations).
-}
inputText : State -> String
inputText state =
    case state of
        PromptState s ->
            Input.text s.input

        ConfirmState _ ->
            ""


{-| Is this a text prompt (vs a yes/no confirmation)?
-}
isPrompt : State -> Bool
isPrompt state =
    case state of
        PromptState _ ->
            True

        ConfirmState _ ->
            False
