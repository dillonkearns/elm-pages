module Tui.Prompt exposing
    ( State, open, text, title
    , withMasking, withSuggestions
    , Result(..), handleKeyEvent
    , viewBody
    )

{-| Text prompt with optional masking and suggestions.

A Prompt is a text input dialog for collecting user input. It builds on
[`Tui.Input`](Tui-Input) and adds masking (for passwords), suggestions
(autocomplete), and a typed `Result` that eliminates boolean checks.

Render with [`Tui.Modal.overlay`](Tui-Modal#overlay):

    case model.prompt of
        Just promptState ->
            Modal.overlay
                { title = Prompt.title promptState
                , body = Prompt.viewBody { width = 40 } promptState
                , footer = "Enter: confirm │ Esc: cancel"
                , width = Modal.defaultWidth ctx.width
                }
                { width = ctx.width, height = ctx.height }
                bgRows

        Nothing ->
            bgRows

Handle keys while the prompt is open:

    case model.prompt of
        Just promptState ->
            case Prompt.handleKeyEvent event promptState of
                ( _, Prompt.Submitted value ) ->
                    handleSubmit value { model | prompt = Nothing }

                ( _, Prompt.Cancelled ) ->
                    ( { model | prompt = Nothing }, Effect.none )

                ( newPrompt, Prompt.Continue ) ->
                    ( { model | prompt = Just newPrompt }, Effect.none )

        Nothing ->
            ...


## Creating a Prompt

@docs State, open, text, title


## Optional Features

@docs withMasking, withSuggestions


## Interaction

@docs Result, handleKeyEvent


## Rendering

@docs viewBody

-}

import Ansi.Color
import Tui
import Tui.Input as Input


{-| Opaque prompt state.
-}
type State
    = State
        { input : Input.State
        , promptTitle : String
        , placeholder : String
        , masked : Bool
        , suggest : Maybe (String -> List String)
        , selectedSuggestion : Int
        }


{-| Open a prompt with a title and optional placeholder text.

    Prompt.open { title = "Branch name", placeholder = "feature/" }

-}
open : { title : String, placeholder : String } -> State
open config =
    State
        { input = Input.init ""
        , promptTitle = config.title
        , placeholder = config.placeholder
        , masked = False
        , suggest = Nothing
        , selectedSuggestion = 0
        }


{-| Get the current text value.
-}
text : State -> String
text (State s) =
    Input.text s.input


{-| Get the prompt title.
-}
title : State -> String
title (State s) =
    s.promptTitle


{-| Enable masked input — shows `*` instead of characters. The real
text is still returned on [`Submitted`](#Result).

    Prompt.open { title = "Password", placeholder = "" }
        |> Prompt.withMasking

-}
withMasking : State -> State
withMasking (State s) =
    State { s | masked = True }


{-| Add a suggestions function. As the user types, matching suggestions
appear below the input. Tab accepts the first suggestion.

    Prompt.open { title = "Fruit", placeholder = "" }
        |> Prompt.withSuggestions
            (\query ->
                allFruits |> List.filter (String.contains query)
            )

-}
withSuggestions : (String -> List String) -> State -> State
withSuggestions suggestFn (State s) =
    State { s | suggest = Just suggestFn }


{-| The result of handling a key event.

  - **`Continue`** — key was handled, keep the prompt open
  - **`Submitted value`** — Enter was pressed, here's the text
  - **`Cancelled`** — Escape was pressed

-}
type Result
    = Continue
    | Submitted String
    | Cancelled


{-| Handle a key event. Returns the updated state and a `Result`.

    case Prompt.handleKeyEvent event promptState of
        ( _, Prompt.Submitted value ) -> handleSubmit value
        ( _, Prompt.Cancelled ) -> closePrompt
        ( newState, Prompt.Continue ) -> keepEditing newState

-}
handleKeyEvent : Tui.KeyEvent -> State -> ( State, Result )
handleKeyEvent event (State s) =
    case event.key of
        Tui.Enter ->
            ( State s, Submitted (Input.text s.input) )

        Tui.Escape ->
            ( State s, Cancelled )

        Tui.Tab ->
            case suggestionsFor s of
                [] ->
                    ( State s, Continue )

                suggestions ->
                    let
                        selectedSuggestion =
                            suggestions
                                |> List.drop s.selectedSuggestion
                                |> List.head
                                |> Maybe.withDefault
                                    (suggestions
                                        |> List.head
                                        |> Maybe.withDefault (Input.text s.input)
                                    )
                    in
                    ( State
                        { s
                            | input = Input.init selectedSuggestion
                            , selectedSuggestion = 0
                        }
                    , Continue
                    )

        Tui.Arrow Tui.Down ->
            case suggestionsFor s of
                [] ->
                    ( State s, Continue )

                suggestions ->
                    ( State
                        { s
                            | selectedSuggestion =
                                min (List.length suggestions - 1) (s.selectedSuggestion + 1)
                        }
                    , Continue
                    )

        Tui.Arrow Tui.Up ->
            case suggestionsFor s of
                [] ->
                    ( State s, Continue )

                _ ->
                    ( State { s | selectedSuggestion = max 0 (s.selectedSuggestion - 1) }, Continue )

        _ ->
            let
                resetSelectedSuggestion : Int
                resetSelectedSuggestion =
                    case event.key of
                        Tui.Character _ ->
                            0

                        Tui.Backspace ->
                            0

                        Tui.Delete ->
                            0

                        _ ->
                            s.selectedSuggestion
            in
            ( State
                { s
                    | input = Input.update event s.input
                    , selectedSuggestion = resetSelectedSuggestion
                }
            , Continue
            )


{-| Render the prompt body. Shows the input field (or masked version),
placeholder when empty, and suggestions if configured.

    Prompt.viewBody { width = 40 } promptState

-}
viewBody : { width : Int } -> State -> List Tui.Screen
viewBody config (State s) =
    let
        currentText =
            Input.text s.input

        inputView =
            if s.masked then
                Input.viewMasked config s.input

            else if String.isEmpty currentText && not (String.isEmpty s.placeholder) then
                Tui.text s.placeholder |> Tui.dim

            else
                Input.view config s.input

        suggestionRows =
            case s.suggest of
                Just _ ->
                    if List.isEmpty (suggestionsFor s) then
                        []

                    else
                        let
                            suggestions =
                                suggestionsFor s
                        in
                        [ Tui.blank ]
                            ++ List.indexedMap
                                (\i suggestion ->
                                    if i == s.selectedSuggestion then
                                        Tui.text ("  " ++ suggestion)
                                            |> Tui.fg Ansi.Color.cyan
                                            |> Tui.bold

                                    else
                                        Tui.text ("  " ++ suggestion)
                                            |> Tui.dim
                                )
                                (List.take 5 suggestions)

                Nothing ->
                    []
    in
    [ Tui.blank
    , inputView
    , Tui.blank
    ]
        ++ suggestionRows


suggestionsFor :
    { a
        | input : Input.State
        , suggest : Maybe (String -> List String)
    }
    -> List String
suggestionsFor s =
    case s.suggest of
        Just suggestFn ->
            let
                query =
                    Input.text s.input
            in
            if String.isEmpty query then
                []

            else
                suggestFn query

        Nothing ->
            []
