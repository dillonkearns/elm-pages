module Tui.Layout.Effect.Internal exposing (Effect(..))

{-| Internal effect type for `Tui.Layout.compileApp` apps. Not exposed from
tui-widgets. Kept separate from [`Tui.Layout.Effect`](Tui-Layout-Effect) so
other tui-widgets modules (`Tui.Layout`) can pattern-match on the constructors
while the public API surface stays opaque.
-}

import Tui.Effect


{-| Layered effect type used by `Tui.Layout.compileApp`. Wraps the core
[`Tui.Effect`](Tui-Effect) type with framework-specific operations for
scrolling, focus, selection, and toast notifications.
-}
type Effect msg
    = Runtime (Tui.Effect.Effect msg)
    | Batch (List (Effect msg))
    | Toast String
    | ErrorToast String
    | ResetScroll String
    | ScrollTo String Int
    | ScrollDown String Int
    | ScrollUp String Int
    | SetSelectedIndex String Int
    | SelectFirst String
    | FocusPane String
