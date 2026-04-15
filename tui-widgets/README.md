# elm-tui-widgets

Lazygit-inspired TUI widgets for [elm-pages](https://elm-pages.com) terminal applications.

Split-pane layouts, selectable lists, modals, fuzzy pickers, keybinding dispatch,
search, toasts — the building blocks for rich terminal UIs, all declarative Elm.

## Design Goals

- **Lazygit as a reference** — lazygit has proven that split panes, modal popups,
  keybinding help, and fuzzy search are the right primitives for terminal UIs. These
  widgets follow those patterns closely.
- **Declarative** — describe your layout as data. The framework manages scroll offsets,
  selection indices, focus, and terminal dimensions in an opaque `State`.
- **Composable** — each widget works standalone or plugs into `Layout.compileApp`.
  Use `Tui.Modal.overlay` with any widget, or use `Layout` which wires modals,
  keybindings, status, and mouse dispatch together for you.
- **Discoverable** — keybinding help screens, options bars, and command palettes
  are generated from the same binding declarations you use for dispatch.
- **Testable** — `Tui.Test` lets you write pure Elm tests that simulate
  keypresses, mouse clicks, and scroll events, then assert on the rendered
  terminal output. No mocking, no real terminal needed.

## Example

A mini git log viewer with two panes, keybindings, and a commit dialog:

```elm
import Tui
import Tui.Effect as Effect
import Tui.Layout as Layout


type Msg
    = SelectCommit Commit
    | OpenCommitDialog
    | SubmitCommit String
    | CloseModal
    | Quit


view : Tui.Context -> Model -> Layout.Layout Msg
view ctx model =
    Layout.horizontal
        [ Layout.pane "commits"
            { title = "Commits", width = Layout.fill }
            (Layout.selectableList
                { onSelect = SelectCommit
                , view =
                    \{ selection } commit ->
                        case selection of
                            Layout.Selected { focused } ->
                                Tui.text ("▸ " ++ commit.sha)
                                    |> (if focused then Tui.bg Ansi.Color.blue else Tui.bold)

                            Layout.NotSelected ->
                                Tui.text ("  " ++ commit.sha)
                }
                model.commits
            )
        , Layout.pane "diff"
            { title = "Diff", width = Layout.fillPortion 2 }
            (Layout.content (List.map Tui.text model.diffLines)
                |> Layout.withSearchable
            )
        ]


bindings : { focusedPane : Maybe String } -> Model -> List (Layout.Group Msg)
bindings _ _ =
    [ Layout.group "Actions"
        [ Layout.charBinding 'c' "Commit" OpenCommitDialog
        , Layout.charBinding 'q' "Quit" Quit
        ]
    ]


modal : Model -> Maybe (Layout.Modal Msg)
modal model =
    if model.showCommitDialog then
        Just
            (Layout.promptModal
                { title = "Commit Message"
                , initialValue = ""
                , onSubmit = SubmitCommit
                , onCancel = CloseModal
                }
            )

    else
        Nothing
```

Wire it all up with `Layout.compileApp`, which handles key routing, focus
management, scroll state, mouse events, status toasts, and modals:

```elm
run : Script
run =
    Tui.Program.program
        (Layout.compileApp
            { data = loadCommits
            , init = init
            , update = update
            , view = view
            , bindings = bindings
            , status = \model -> { waiting = model.activeOp }
            , modal = modal
            , onRawEvent = Nothing
            }
        )
```

See the full working example in
[`examples/end-to-end/script/src/MiniGit.elm`](https://github.com/dillonkearns/elm-pages/blob/master/examples/end-to-end/script/src/MiniGit.elm).

## Testing

TUI apps built with `Layout.compileApp` are fully testable with `Tui.Test` —
simulate keypresses, mouse clicks, and scroll events, then assert on the
rendered terminal output. No mocking, no DOM — just pure Elm:

```elm
import Tui.Test as TuiTest

suite : Test
suite =
    describe "MiniGit"
        [ test "j/k navigates the commit list" <|
            \() ->
                TuiTest.startApp () appConfig
                    |> TuiTest.ensureViewHas "▸ abc123"
                    |> TuiTest.pressKey 'j'
                    |> TuiTest.ensureViewHas "▸ def456"
                    |> TuiTest.expectRunning
        , test "c opens the commit dialog" <|
            \() ->
                TuiTest.startApp () appConfig
                    |> TuiTest.pressKey 'c'
                    |> TuiTest.ensureViewHas "Commit Message"
                    |> TuiTest.expectRunning
        , test "? opens help, Esc closes it" <|
            \() ->
                TuiTest.startApp () appConfig
                    |> TuiTest.pressKey '?'
                    |> TuiTest.ensureViewHas "Keybindings"
                    |> TuiTest.pressKeyWith { key = Tui.Escape, modifiers = [] }
                    |> TuiTest.ensureViewDoesNotHave "Keybindings"
                    |> TuiTest.expectRunning
        , test "clicking a link fires the link callback" <|
            \() ->
                TuiTest.startApp () appConfig
                    |> TuiTest.clickText "docs link"
                    |> TuiTest.ensureViewHas "clicked: https://example.com"
                    |> TuiTest.expectRunning
        ]
```

Tests run with `elm-test` — no terminal needed. The test runner gives you
a simulated terminal context with configurable dimensions, so you can test
scroll behavior, layout reflow, and off-screen content.

## Modules

### Layout

| Module | Description |
|--------|-------------|
| [`Tui.Layout`](Tui-Layout) | Split-pane layout engine — the main orchestrator. Manages panes, selection, scroll, focus, tabs, keybindings, modals, and mouse dispatch in one opaque `State`. |

### Modals & Dialogs

| Module | Description |
|--------|-------------|
| [`Tui.Modal`](Tui-Modal) | Centered bordered overlay — the rendering primitive that all modal widgets use. |
| [`Tui.Picker`](Tui-Picker) | Fuzzy-filtered searchable list popup. Type to narrow, j/k to navigate. |
| [`Tui.CommandPalette`](Tui-CommandPalette) | Command palette built on Picker — browse and execute keybinding actions. |
| [`Tui.Menu`](Tui-Menu) | Direct-dispatch menu with sections and disabled items. Unlike Picker, keys fire immediately. |
| [`Tui.Confirm`](Tui-Confirm) | Yes/No confirmation dialog. |
| [`Tui.Prompt`](Tui-Prompt) | Text input dialog with optional masking and suggestions. |

### Status & Feedback

| Module | Description |
|--------|-------------|
| [`Tui.Status`](Tui-Status) | Unified status bar — toasts, waiting spinners, and error messages in one module. |
| [`Tui.Toast`](Tui-Toast) | Standalone auto-dismissing toast notifications. Prefer `Tui.Status` for new code. |
| [`Tui.Spinner`](Tui-Spinner) | Stateless `\|`, `/`, `-`, `\` spinner animation. |

### Keybindings & Navigation

| Module | Description |
|--------|-------------|
| [`Tui.Keybinding`](Tui-Keybinding) | Declarative keybinding groups — dispatch, help screen generation, and formatting. |
| [`Tui.OptionsBar`](Tui-OptionsBar) | Bottom-of-screen keybinding hints (like lazygit's footer). |
| [`Tui.Search`](Tui-Search) | In-pane text search with smart-case matching and `n`/`N` navigation. |

### Utilities

| Module | Description |
|--------|-------------|
| [`Tui.FuzzyMatch`](Tui-FuzzyMatch) | Fuzzy string matching — used by Picker internally, useful for custom filtering. |

## Installation

```bash
elm install dillonkearns/elm-tui-widgets
```

This package depends on [`dillonkearns/elm-pages`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/)
for the core `Tui` primitives (`Tui.Screen`, `Tui.Effect`, `Tui.Sub`, etc.).

## Learning Resources

- [elm-pages TUI guide](https://elm-pages.com) — getting started with `Tui.Program`
- [`examples/end-to-end/script/src/MiniGit.elm`](https://github.com/dillonkearns/elm-pages/blob/master/examples/end-to-end/script/src/MiniGit.elm) — full working example
- [Elm package docs](https://package.elm-lang.org/packages/dillonkearns/elm-tui-widgets/latest/) — API reference with examples in every module
