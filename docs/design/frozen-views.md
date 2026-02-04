# Frozen Views Design Document

## Overview

This document describes the design for "frozen views" in elm-pages - a feature that enables dead-code elimination of view dependencies (like markdown parsers, syntax highlighters) while preserving server-rendered HTML through virtual-dom adoption.

## Goals

1. **DCE for frozen view code** - Code used only to render frozen content (markdown parsers, syntax highlighters, etc.) should be eliminated from the client bundle
2. **DCE for ephemeral data** - Data used only to render frozen content should not be sent to the client
3. **No content flash** - Pre-rendered HTML should be adopted by the virtual-dom, not replaced and re-rendered
4. **SPA navigation support** - Client-side navigation should work by parsing HTML strings
5. **Type-safe boundaries** - The Elm type system should enforce what can be accessed in frozen vs dynamic regions
6. **Simple mental model** - Users write normal Elm code; elm-pages optimizes it

## Non-Goals

- Zero-JS pages (elm-pages philosophy is that interactivity shouldn't require sacrificing DX)
- True "islands" architecture with multiple independent Elm apps
- Partial hydration (we hydrate the full app, but frozen views are frozen)

## Key Concepts

### Frozen vs Dynamic Content

**Frozen content:**
- Content that doesn't depend on `Model` or runtime fields like `app.action`, `app.navigation`, `app.url`
- Rendered at build/request time
- HTML is "frozen" - never re-rendered on the client
- Dependencies (parsers, source data) are DCE'd from client bundle

**Dynamic content:**
- Content that depends on `Model` or runtime app fields
- Hydrated and updated normally by the virtual-dom

### Data Types: Data vs Ephemeral

```elm
-- Route module defines Data with all fields
type alias Data =
    { title : String           -- Used by both freeze and dynamic content
    , renderedMarkdown : Html Never  -- Only used in View.freeze
    , commentCount : Int       -- Used in dynamic content
    }

-- The build system generates Ephemeral (original full type) and narrows Data
-- Ephemeral = full Data type for use in View.freeze
-- Data (narrowed) = only fields accessed outside of freeze calls
```

The elm-review codemod analyzes field access patterns:
- Fields accessed ONLY inside `View.freeze` calls are removed from the client-side `Data` type
- This enables DCE of the field accessors and any rendering code that depends on them

## Architecture

### User API

```elm
-- In View.elm (user-defined)
type alias Freezable =
    Html Never

freeze : Freezable -> Html msg
freeze content =
    content
        |> freezableToHtml
        |> htmlToFreezable
        |> Html.map never

-- In Route module
view : App Data ActionData RouteParams -> Model -> View Msg
view app model =
    { title = app.data.title
    , body =
        [ -- Frozen content: only app.data accessible, NOT model
          View.freeze
              (Html.div []
                  [ Html.text app.data.title
                  , app.data.renderedMarkdown
                  ]
              )

        -- Dynamic content: Model and app fields accessible
        , Html.div []
            [ Html.text (String.fromInt model.count)
            , Html.text (String.fromInt app.data.commentCount)
            ]
        ]
    }
```

### Build-Time Transformation

**Server bundle:** Contains everything, `View.freeze` wraps content with `data-static` attribute markers.

**Client bundle transformation (via elm-review codemod):**
```elm
-- BEFORE (source code)
View.freeze
    (Html.div []
        [ Html.text app.data.title
        , app.data.renderedMarkdown
        ]
    )

-- AFTER (client bundle)
Html.Lazy.lazy (\_ -> Html.text "") "__ELM_PAGES_STATIC__0"
    |> View.htmlToFreezable
    |> Html.map never
```

The original lambda body is unreferenced → DCE'd along with all dependencies.

### Runtime Flow

#### Initial Page Load

1. Browser receives pre-rendered HTML with frozen views:
   ```html
   <div data-url="/my-page">
     <div data-static="0"><h1>My Post</h1><p>Content...</p></div>
     <div><!-- dynamic content --></div>
   </div>
   ```

2. Elm app initializes, calls `_VirtualDom_render` on root VDOM

3. When render encounters the frozen view thunk (magic string `__ELM_PAGES_STATIC__`):
   - Queries for `[data-static="0"]`
   - Detaches node from old tree
   - Returns the existing DOM node (doesn't create new one)
   - Stores virtualized version in `vNode.k` for future diff comparison

4. `replaceChild` swaps trees - adopted nodes are now in new tree

5. Subsequent renders: refs always match → `y.k = x.k` → no diffing

#### SPA Navigation

1. User clicks internal link, elm-pages fetches new page data:
   - `content.dat` contains: `[frozen views JSON length][frozen views JSON][response bytes]`
   - Frozen views JSON: `{ "0": "<div data-static='0'><h1>Other Post</h1>...</div>" }`

2. JavaScript stores frozen views in `window.__ELM_PAGES_FROZEN_VIEWS__`

3. Elm receives page data, triggers re-render

4. When render encounters the thunk:
   - Looks up HTML in `window.__ELM_PAGES_FROZEN_VIEWS__`
   - Parses HTML string via template element
   - Returns parsed DOM node

5. Subsequent renders: refs match → frozen, no diffing

## Implementation Details

### Virtual-Dom Codemod

Patch the thunk case (tag === 5) in `_VirtualDom_render`:

```javascript
if (tag === 5) {
    var refs = vNode.l;

    // Check for frozen view marker: refs[0] is magic string prefix
    if (refs.length === 1 &&
        typeof refs[0] === 'string' &&
        refs[0].startsWith('__ELM_PAGES_STATIC__')) {

        var frozenId = refs[0].substring('__ELM_PAGES_STATIC__'.length);

        // Case 1: Initial load - adopt existing DOM
        var existingDom = document.querySelector('[data-static="' + frozenId + '"]');
        if (existingDom) {
            if (existingDom.parentNode) {
                existingDom.parentNode.removeChild(existingDom);
            }
            vNode.k = _VirtualDom_virtualize(existingDom);
            return existingDom;
        }

        // Case 2: SPA navigation - get from global
        var frozenViews = window.__ELM_PAGES_FROZEN_VIEWS__;
        if (frozenViews && frozenViews[frozenId]) {
            var template = document.createElement('template');
            template.innerHTML = frozenViews[frozenId];
            var newDom = template.content.firstElementChild;
            vNode.k = _VirtualDom_virtualize(newDom);
            return newDom;
        }

        // Case 3: Fallback - empty text node
        return document.createTextNode('');
    }

    // Original thunk behavior
    return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
}
```

### Data Type Transformation (elm-review)

The `StaticViewTransform` rule:

1. Tracks which `app.data` fields are accessed in client context (outside `View.freeze`)
2. Tracks which fields are accessed only in ephemeral context (inside `View.freeze` or `head`)
3. Transforms the `Data` type alias to remove ephemeral-only fields
4. Generates an `Ephemeral` type alias with all original fields
5. Updates helper function type annotations that take `Data` → `Ephemeral` if only called from freeze
6. Stubs out `head` and `data` functions (they never run on client)

### Taint Tracking (elm-review)

The `StaticRegionScope` rule prevents errors by tracking "taint" - values that depend on runtime state:

1. `model` and its fields are tainted
2. Runtime app fields (`app.action`, `app.navigation`, `app.url`, etc.) are tainted
3. Variables bound to tainted values are tainted
4. Function calls that pass tainted values through are tracked

If tainted values are used inside `View.freeze`, the rule reports an error with helpful suggestions.

## Data Flow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    BUILD/REQUEST TIME                            │
├─────────────────────────────────────────────────────────────────┤
│  1. Resolve Data (markdown sources, etc.)                       │
│  2. Run view with full Data type                                │
│  3. View.freeze regions wrapped with data-static attributes     │
│  4. Extract frozen view HTML strings                            │
│  5. Pre-render full page HTML                                   │
│  6. Store frozen views in content.dat prefix                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CLIENT BUNDLE                                 │
├─────────────────────────────────────────────────────────────────┤
│  elm-review transforms:                                         │
│  - View.freeze → Html.Lazy.lazy with magic string              │
│  - Data type narrowed (ephemeral fields removed)               │
│  - head/data functions stubbed                                 │
│                                                                  │
│  Elm compiler DCE eliminates:                                   │
│  - Markdown parser                                              │
│  - Syntax highlighter                                           │
│  - Ephemeral field accessors                                    │
│  - Original View.freeze content                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DATA PAYLOAD TO CLIENT                        │
├─────────────────────────────────────────────────────────────────┤
│  content.dat format:                                            │
│  [4 bytes: frozen views JSON length]                            │
│  [N bytes: frozen views JSON]                                   │
│    { "0": "<div data-static='0'>...</div>", ... }              │
│  [remaining: ResponseSketch bytes]                              │
│    Data contains only client-used fields                        │
│                                                                  │
│  NOT included: raw markdown, parser code, ephemeral fields      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CLIENT RUNTIME                                │
├─────────────────────────────────────────────────────────────────┤
│  Initial load:                                                  │
│  - Patched vdom finds existing DOM via data-static attribute    │
│  - Adopts DOM node, no re-render, no flash                      │
│                                                                  │
│  SPA navigation:                                                │
│  - JS fetches content.dat, extracts frozen views JSON           │
│  - Stores in window.__ELM_PAGES_FROZEN_VIEWS__                  │
│  - Patched vdom parses HTML string from global                  │
│  - Inserts parsed DOM                                           │
│                                                                  │
│  Subsequent renders:                                            │
│  - Thunk refs match (same magic string) → no diffing            │
│  - Frozen views completely frozen                               │
└─────────────────────────────────────────────────────────────────┘
```

## Constraints and Limitations

1. **Frozen content must be `Html Never`** - No event handlers allowed (no `onClick`, etc.)
2. **Only works in Route modules** - The elm-review transformation only applies to Route modules
3. **Model cannot be used in freeze** - Compile-time taint checking prevents this
4. **Runtime app fields cannot be used in freeze** - `app.action`, `app.navigation`, `app.url`, etc.

## Version Mismatch Considerations

**What happens if client code is on a different version than server data?**

Current behavior: elm-pages detects version mismatch and triggers full page reload.

With frozen views: Same behavior applies. The frozen HTML is just "data" from the client's perspective. If there's a version mismatch:
- Content hash check fails (existing mechanism)
- Full page reload occurs
- Client gets fresh HTML with matching version

## References

- User documentation: /docs/frozen-views
- Taint tracking rule: `generator/review/src/Pages/Review/StaticRegionScope.elm`
- Data type transform: `generator/dead-code-review/src/Pages/Review/StaticViewTransform.elm`
- Virtual-dom codemod: `generator/src/frozen-view-codemod.js`
