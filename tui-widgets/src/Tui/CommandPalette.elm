module Tui.CommandPalette exposing
    ( State, open
    , typeChar, backspace, navigateDown, navigateUp
    , selected, viewBody, viewFooter, title
    )

{-| Command palette — browse and execute keybinding actions in one step.
Built on [`Tui.Picker`](Tui-Picker) and [`Tui.Keybinding`](Tui-Keybinding).

    -- Open with current keybinding groups:
    CommandPalette.open (activeBindings model)

    -- In update:
    case event.key of
        Tui.Escape -> closeCommandPalette
        Tui.Enter ->
            case CommandPalette.selected model.palette of
                Just action -> handleAction action model
                Nothing -> ( model, Effect.none )
        Tui.Backspace -> { model | palette = CommandPalette.backspace model.palette }
        Tui.Character c -> { model | palette = CommandPalette.typeChar c model.palette }
        Tui.Arrow Tui.Down -> { model | palette = CommandPalette.navigateDown model.palette }
        Tui.Arrow Tui.Up -> { model | palette = CommandPalette.navigateUp model.palette }

    -- Render with Modal.overlay:
    Modal.overlay
        { title = CommandPalette.title
        , body = CommandPalette.viewBody model.palette
        , footer = CommandPalette.viewFooter model.palette
        , width = 50
        }
        dims bgRows

@docs State, open
@docs typeChar, backspace, navigateDown, navigateUp
@docs selected, viewBody, viewFooter, title

-}

import Ansi.Color
import Tui
import Tui.FuzzyMatch as FuzzyMatch
import Tui.Keybinding as Keybinding


{-| Opaque command palette state.
-}
type State action
    = State
        { entries : List (Entry action)
        , filterText : String
        , selectedIndex : Int
        }


type alias Entry action =
    { keyLabel : String
    , description : String
    , action : action
    }


{-| Open the command palette with keybinding groups.
-}
open : List (Keybinding.Group action) -> State action
open groups =
    State
        { entries =
            groups
                |> List.concatMap
                    (\group ->
                        group.bindings
                            |> List.map
                                (\binding ->
                                    { keyLabel = Keybinding.formatBinding binding
                                    , description = binding.description
                                    , action = binding.action
                                    }
                                )
                    )
        , filterText = ""
        , selectedIndex = 0
        }


{-| Type a character into the filter.
-}
typeChar : Char -> State action -> State action
typeChar c (State s) =
    State { s | filterText = s.filterText ++ String.fromChar c, selectedIndex = 0 }


{-| Delete the last character.
-}
backspace : State action -> State action
backspace (State s) =
    State { s | filterText = String.dropRight 1 s.filterText, selectedIndex = 0 }


{-| Move selection down.
-}
navigateDown : State action -> State action
navigateDown (State s) =
    let
        maxIdx =
            max 0 (List.length (getVisible s) - 1)
    in
    State { s | selectedIndex = min maxIdx (s.selectedIndex + 1) }


{-| Move selection up.
-}
navigateUp : State action -> State action
navigateUp (State s) =
    State { s | selectedIndex = max 0 (s.selectedIndex - 1) }


{-| Get the selected action.
-}
selected : State action -> Maybe action
selected (State s) =
    getVisible s
        |> List.drop s.selectedIndex
        |> List.head
        |> Maybe.map .action


{-| The palette title.
-}
title : String
title =
    "Actions"


{-| Render the palette body.
-}
viewBody : State action -> List Tui.Screen
viewBody (State s) =
    let
        entries =
            getVisible s

        filterRow =
            Tui.concat
                [ Tui.text "/ " |> Tui.dim
                , if String.isEmpty s.filterText then
                    Tui.text " " |> Tui.inverse

                  else
                    Tui.concat
                        [ Tui.text s.filterText
                        , Tui.text " " |> Tui.inverse
                        ]
                ]

        entryRows =
            entries
                |> List.indexedMap
                    (\i entry ->
                        let
                            isSelected =
                                i == s.selectedIndex
                        in
                        if isSelected then
                            Tui.spaced
                                [ Tui.text entry.keyLabel |> Tui.fg Ansi.Color.cyan |> Tui.bold
                                , Tui.text entry.description
                                ]
                                |> Tui.bg Ansi.Color.blue

                        else
                            Tui.spaced
                                [ Tui.text entry.keyLabel |> Tui.fg Ansi.Color.cyan
                                , Tui.text entry.description
                                ]
                    )
    in
    filterRow :: Tui.blank :: entryRows


{-| Render a footer string.
-}
viewFooter : State action -> String
viewFooter (State s) =
    let
        count =
            List.length (getVisible s)
    in
    String.fromInt count ++ " actions │ Enter: execute │ Esc: cancel"



-- INTERNAL


getVisible : { a | entries : List (Entry action), filterText : String } -> List (Entry action)
getVisible s =
    if String.isEmpty s.filterText then
        s.entries

    else
        s.entries
            |> List.filterMap
                (\entry ->
                    if FuzzyMatch.match s.filterText entry.description then
                        Just ( FuzzyMatch.score s.filterText entry.description, entry )

                    else if FuzzyMatch.match s.filterText entry.keyLabel then
                        Just ( FuzzyMatch.score s.filterText entry.keyLabel, entry )

                    else
                        Nothing
                )
            |> List.sortBy (\( sc, _ ) -> negate sc)
            |> List.map Tuple.second
