# Static Regions Design Document

## Overview

This document describes the design for "static regions" in elm-pages - a feature that enables dead-code elimination of view dependencies (like markdown parsers, syntax highlighters) while preserving server-rendered HTML through virtual-dom adoption.

## Goals

1. **DCE for static view code** - Code used only to render static content (markdown parsers, syntax highlighters, etc.) should be eliminated from the client bundle
2. **DCE for static data** - Data used only to render static content should not be sent to the client
3. **No content flash** - Pre-rendered HTML should be adopted by the virtual-dom, not replaced and re-rendered
4. **SPA navigation support** - Client-side navigation should work by parsing HTML strings
5. **Type-safe boundaries** - The Elm type system should enforce what can be accessed in static vs dynamic regions
6. **Simple mental model** - Users write normal Elm code; elm-pages optimizes it

## Non-Goals

- Zero-JS pages (elm-pages philosophy is that interactivity shouldn't require sacrificing DX)
- True "islands" architecture with multiple independent Elm apps
- Partial hydration (we hydrate the full app, but static regions are frozen)

## Key Concepts

### Static vs Dynamic Regions

**Static regions:**
- Content that doesn't depend on `Model` or runtime `Data`
- Rendered at build/request time
- HTML is "frozen" - never re-rendered on the client
- Dependencies (parsers, source data) are DCE'd from client bundle

**Dynamic regions:**
- Content that depends on `Model` or runtime `Data`
- Hydrated and updated normally by the virtual-dom

### The With-Context Pattern

Inspired by `elm-ui-with-context`, we use context types to control access:

```elm
type Context staticData data model msg
type StaticContext staticData      -- Can only access StaticData
type DynamicContext data model     -- Can access Data and Model, NOT StaticData
```

This enforces at the type level that static regions cannot access runtime state.

## Architecture

### Data Types

```elm
-- Route module defines both static and dynamic data
type alias StaticData =
    { renderedMarkdown : String
    , highlightedCode : List String
    }

type alias Data =
    { commentCount : Int
    , currentUser : Maybe User
    }

-- StaticData resolved at build time, produces HTML strings
staticData : RouteParams -> BackendTask FatalError StaticData
staticData params =
    BackendTask.map2 StaticData
        (getMarkdown params.slug |> BackendTask.map Markdown.toHtml)
        (getCodeSnippets params.slug |> BackendTask.map (List.map SyntaxHighlight.toHtml))

-- Data resolved at request time, sent to client
data : RouteParams -> BackendTask FatalError Data
data params =
    BackendTask.map2 Data
        (getCommentCount params.slug)
        (getCurrentUser)
```

### View API

```elm
view : View.Context StaticData Data Model Msg -> Html Msg
view context =
    Html.div []
        [ -- Static region: only StaticData accessible
          View.static context "markdown"
              (\staticCtx ->
                  Html.Raw.html (View.staticData staticCtx).renderedMarkdown
              )

        -- Dynamic region: Data and Model accessible, NOT StaticData
        , View.dynamic context
              (\dynamicCtx ->
                  Html.div []
                      [ Html.text (String.fromInt (View.data dynamicCtx).commentCount)
                      , Html.text (View.model dynamicCtx).draftComment
                      ]
              )
        ]
```

### Build-Time Transformation

**Server bundle:** Contains everything, runs `staticData` and `View.static` functions.

**Client bundle transformation (via codemod):**
```elm
-- BEFORE (source code)
View.static context "markdown"
    (\staticCtx -> Html.Raw.html (View.staticData staticCtx).renderedMarkdown)

-- AFTER (client bundle)
View.adopt "markdown" (View.getStaticHtml context "markdown")
```

The original lambda body is unreferenced → DCE'd along with all dependencies.

### Runtime Flow

#### Initial Page Load

1. Browser receives pre-rendered HTML with static regions:
   ```html
   <div data-elm>
     <div data-static="markdown"><h1>My Post</h1><p>Content...</p></div>
     <div><!-- dynamic content placeholder --></div>
   </div>
   ```

2. Elm app initializes, calls `_VirtualDom_render` on root VDOM

3. When render encounters our special thunk (the `View.adopt` call):
   - Queries for `[data-static="markdown"]`
   - Detaches node from old tree
   - Returns the existing DOM node (doesn't create new one)
   - Stores virtualized version in `__node` for future diff comparison

4. `replaceChild` swaps trees - adopted nodes are now in new tree

5. Subsequent renders: refs always match → `y.__node = x.__node` → no diffing

#### SPA Navigation

1. User clicks internal link, elm-pages fetches new page data:
   ```javascript
   {
     data: { commentCount: 42, ... },
     staticHtml: {
       "markdown": "<div data-static='markdown'><h1>Other Post</h1>...</div>"
     }
   }
   ```

2. View renders with new context containing `staticHtml` dict

3. When render encounters the thunk:
   - No existing `[data-static="markdown"]` in DOM (wrong page)
   - Falls back to parsing `staticHtml` string:
     ```javascript
     var template = document.createElement('template');
     template.innerHTML = htmlFallback;
     var newDom = template.content.firstElementChild;
     ```
   - Returns parsed DOM node

4. Subsequent renders: refs match → frozen, no diffing

## Implementation Details

### Virtual-Dom Codemod

Patch the thunk case in `_VirtualDom_render`:

```javascript
if (tag === __2_THUNK)
{
    var refs = vNode.__refs;

    // Check for static region marker
    if (refs.length >= 3 && refs[1] && refs[1].$ === 'StaticId') {
        var id = refs[1].a;
        var htmlFallback = refs[2];

        // Case 1: Initial load - adopt existing DOM
        var existingDom = _VirtualDom_doc.querySelector('[data-static="' + id + '"]');
        if (existingDom) {
            if (existingDom.parentNode) {
                existingDom.parentNode.removeChild(existingDom);
            }
            vNode.__node = _VirtualDom_virtualize(existingDom);
            return existingDom;
        }

        // Case 2: SPA navigation - parse HTML string
        if (htmlFallback) {
            var template = _VirtualDom_doc.createElement('template');
            template.innerHTML = htmlFallback;
            var newDom = template.content.firstElementChild;
            vNode.__node = _VirtualDom_virtualize(newDom);
            return newDom;
        }

        // Case 3: No content (shouldn't happen)
        return _VirtualDom_doc.createTextNode('');
    }

    // Original thunk behavior
    return _VirtualDom_render(vNode.__node || (vNode.__node = vNode.__thunk()), eventNode);
}
```

### Elm API

```elm
module View.Static exposing (StaticId, adopt)

type StaticId = StaticId String

adopt : String -> String -> Html msg
adopt id htmlFallback =
    Html.Lazy.lazy2 (\_ _ -> Html.text "") (StaticId id) htmlFallback
```

The thunk function `(\_ _ -> Html.text "")` is never called due to the codemod short-circuit.

### DCE Codemod (elm-review rule)

Similar to existing `DeadCodeEliminateData` rule:

1. Find `View.static context id (\staticCtx -> ...)` calls
2. Replace with `View.adopt id (View.getStaticHtml context id)`
3. Original lambda becomes unreferenced → Elm compiler DCE's it

## Version Mismatch Considerations

**Question:** What happens if client code is on a different version than server data?

**Current behavior:** elm-pages detects version mismatch and triggers full page reload.

**With static regions:** Same behavior applies. The static HTML is just "data" from the client's perspective - opaque content to display. If there's a version mismatch:
- The content hash check will fail (existing mechanism)
- Full page reload occurs
- Client gets fresh HTML with matching version

The static HTML string is no different from any other data field in terms of version compatibility. It's simpler in some ways because it doesn't require decoding - it's just raw HTML.

## Data Flow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    BUILD/REQUEST TIME                            │
├─────────────────────────────────────────────────────────────────┤
│  1. Resolve StaticData (markdown sources, etc.)                 │
│  2. Run view with full context                                  │
│  3. View.static regions render to HTML strings                  │
│  4. Store HTML strings in page data payload                     │
│  5. Pre-render full page HTML                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CLIENT BUNDLE                                 │
├─────────────────────────────────────────────────────────────────┤
│  Codemod transforms:                                            │
│  - View.static → View.adopt                                     │
│  - StaticData references removed                                │
│                                                                  │
│  DCE eliminates:                                                │
│  - Markdown parser                                              │
│  - Syntax highlighter                                           │
│  - StaticData type and functions                                │
│  - Original View.static lambda bodies                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DATA PAYLOAD TO CLIENT                        │
├─────────────────────────────────────────────────────────────────┤
│  {                                                              │
│    data: { commentCount: 42, currentUser: {...} },              │
│    staticHtml: {                                                │
│      "markdown": "<div data-static='markdown'>...</div>",       │
│      "code": "<pre data-static='code'>...</pre>"                │
│    }                                                            │
│  }                                                              │
│                                                                  │
│  NOT included: raw markdown, parser code, StaticData            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CLIENT RUNTIME                                │
├─────────────────────────────────────────────────────────────────┤
│  Initial load:                                                  │
│  - View.adopt finds existing DOM, adopts it                     │
│  - No re-render, no flash                                       │
│                                                                  │
│  SPA navigation:                                                │
│  - View.adopt parses HTML string from payload                   │
│  - Inserts parsed DOM                                           │
│                                                                  │
│  Subsequent renders:                                            │
│  - Refs match (same id, same html) → no diffing                 │
│  - Static regions completely frozen                             │
└─────────────────────────────────────────────────────────────────┘
```

## Open Questions

1. **Nested static regions** - Can static regions contain other static regions? Probably not needed initially.

2. **Event handlers in static HTML** - Should we allow onclick etc in static HTML strings? Probably not - if you need interactivity, use a dynamic region.

3. **Streaming/chunked rendering** - How does this interact with streaming HTML responses? The static HTML would need to be complete before hydration.

4. **Error boundaries** - What happens if HTML parsing fails? Probably render a placeholder and log error.

5. **Multiple roots** - What if there are multiple elements with same `data-static` id? Use `querySelector` (first match) and document that IDs must be unique.

## Proof of Concept Plan

1. **Hardcode a simple example** - Single route with one static region
2. **Test initial adoption** - Pre-rendered HTML gets adopted without flash
3. **Test SPA navigation** - HTML string gets parsed and displayed
4. **Test frozen diffing** - Verify static region never re-renders after adoption
5. **Measure bundle size** - Confirm dependencies are eliminated

## References

- Original brainstorm: https://gist.github.com/dillonkearns/7758fdf7a580f5e1d92d316f483f0cd5
- elm-ui-with-context pattern: https://package.elm-lang.org/packages/miniBill/elm-ui-with-context/latest/
- elm-pages DeadCodeEliminateData: `generator/dead-code-review/src/Pages/Review/DeadCodeEliminateData.elm`
