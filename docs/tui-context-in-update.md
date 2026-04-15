# [RESOLVED] Pass Context to update

> **Resolution**: superseded by the current API. `Tui.Layout.compileApp` now
> passes a `Tui.Layout.UpdateContext` record (`context`, `focusedPane`,
> `scrollPosition`, `selectedIndex`) to the user's update function.
> For apps built with plain `Tui.program` (not `Layout.compileApp`),
> subscribe to `Tui.Sub.onResize` and store dimensions in your model.
> This design note is preserved for historical context. The references to
> `Tui.Internal` / `Tui.Internal.run` below are obsolete — the run loop now
> lives in `src/Tui.elm` directly.

## Problem

The TUI framework passes `Context` (terminal width/height) to `view` but not
to `update`. This means `update` can't access terminal dimensions, which breaks
Layout's mouse hit-testing for proportional pane splits.

The `Tui.Internal` loop has the `Context` available at the exact point where
it calls `config.update`:

```elm
-- src/Tui/Internal.elm, processBatchedEvents, ~line 222
config.update msg model
-- `context` is in scope here but not passed
```

## Why it matters

`Layout.handleMouse` needs the terminal width to resolve `Fill`/`FillPortion`
splits into absolute column positions for hit-testing. Without the correct
width, mouse events dispatch to the wrong pane.

Currently MiniGit uses `Layout.contextOf model.layout` which returns 80x24
(the default), so pane boundaries are wrong on wider terminals.

## Attempted fix: Add Context to update signature

Changed `update : msg -> model -> ( model, Effect msg )` to
`update : Context -> msg -> model -> ( model, Effect msg )`.

This triggers an Elm compiler bug:

```
elm: thread blocked indefinitely in an MVar operation
```

The crash happens when `Context ->` is added to the update function type
inside the config record. The same crash occurs whether `Context` is the
type alias or the inlined `{ width : Int, height : Int }`. It also crashes
when only the `Tui.Internal.run` record is changed (before changing any
user code).

The bug appears related to complex record types with multiple function
fields that share type parameters.

## Workaround options

1. **Store context in model from init**: The `data` BackendTask runs after
   `tuiInit`, but `init` doesn't receive the terminal dimensions.

2. **Pass Context as a separate argument** (not in the record): Bypass the
   compiler bug by passing `update` outside the config record:
   ```elm
   run : (Context -> msg -> model -> ...) -> { init : ..., view : ..., ... } -> ...
   ```

3. **Framework stores context in a shared location**: Have the framework
   update the Layout.State's context before calling update. This requires
   the framework to know about Layout.State.

4. **Add onResize subscription back**: Let users subscribe to resize events
   and store terminal dimensions in their model.

## Current state

`Layout.handleMouse` accepts `{ width, height }` as a parameter. MiniGit
passes `Layout.contextOf model.layout` which returns the stale 80x24 default.
Pane hit-testing works correctly for 80-column terminals but is wrong for
wider ones.

The scroll behavior defaults to scrolling the left-most pane's region because
the boundary calculation uses the wrong width.
