# Proposed Design for Static Regions with elm-safe-virtual-dom

## Key Insight from README

elm-safe-virtual-dom already supports server-side rendering adoption:

> If you do server-side rendering and expect Elm to hydrate/virtualize/adopt/take charge over the server-side rendered HTML, you need to make sure that all elements (except the root element) has `data-elm`.

The `_VirtualDom_virtualize` function already "adopts" existing DOM at app startup, building the tNode tracking tree for it.

## The Bug in Our Current Approach

Our codemod does this:

```javascript
var __existingDom = document.querySelector('[data-static="' + __staticId + '"]');
if (__existingDom) {
    if (__existingDom.parentNode) __existingDom.parentNode.removeChild(__existingDom);  // ← PROBLEM!
    // ... then try to return it
}
```

**We're removing the DOM from the document**, which breaks elm-safe-virtual-dom's virtualize mechanism:

1. Virtualize runs at startup, creates tNode with `__domNode` pointing to static region element
2. Element is in document at correct position
3. Our codemod finds it and REMOVES it
4. When `applyPatchRedraw` runs, `tNode.__domNode.parentNode` is null
5. Insertion fails

We're fighting against the built-in SSR adoption!

## The Real Challenge

Even without our buggy removal, there's still a type mismatch:

- Virtualized DOM → regular node vNode (tag 2)
- Static region in view → thunk vNode (tag 5)

Type 2 ≠ Type 5 → diff triggers REDRAW → thunk gets evaluated → we lose the "don't run heavy code" benefit

## Proposed Design

### Principle: Don't fight virtualize, extend it

Instead of intercepting in `_VirtualDom_render`, hook earlier in `_VirtualDom_diffHelp`.

### Hook Point: Thunk vs Non-Thunk Comparison

```javascript
// In _VirtualDom_diffHelp, when comparing different types:

if (xType !== yType) {
    // NEW: Check for static region adoption
    if (_VirtualDom_canAdoptAsStaticRegion(x, y, tNode)) {
        // Keep existing DOM, skip thunk evaluation
        return {
            __domNode: tNode.__domNode,
            __translated: false,
            __reinsert: false
        };
    }

    // ... existing type mismatch handling (upkey, REDRAW, etc.)
}
```

### The Adoption Check

```javascript
function _VirtualDom_canAdoptAsStaticRegion(oldVNode, newVNode, tNode) {
    // New must be a thunk
    if (newVNode.$ !== __2_THUNK) return false;

    // Check if it's a static region thunk
    var refs = newVNode.__refs;
    if (!refs || refs.length < 2) return false;
    if (refs[1].$ !== 'StaticId' && refs[1].$ !== 0) return false;

    var newStaticId = refs[1].a;

    // Old must be a virtualized node with matching data-static
    var domNode = tNode.__domNode;
    if (!domNode || domNode.nodeType !== 1) return false;

    var oldStaticId = domNode.getAttribute('data-static');

    return oldStaticId === newStaticId;
}
```

### What This Achieves

| Scenario | Behavior |
|----------|----------|
| Initial load | Virtualize adopts DOM. Diff sees static region thunk vs virtualized node. Hook recognizes match → keeps existing DOM, skips thunk evaluation. |
| SPA navigation | No existing DOM. Thunk must be evaluated. Use `__ELM_PAGES_STATIC_REGIONS__` to get HTML, parse to DOM, use `__reinsert: true`. |
| Re-render (same page) | Thunk refs match → normal thunk caching, DOM unchanged. |

### For SPA Navigation

The thunk-vs-thunk path needs to handle the case where we're navigating to a new page:

```javascript
// In thunk comparison when refs don't match:
if (x.$ === __2_THUNK && y.$ === __2_THUNK) {
    // ... refs comparison ...
    if (!same) {
        // Check if this is a static region with HTML available
        var staticId = getStaticIdFromThunk(y);
        var htmlString = (window.__ELM_PAGES_STATIC_REGIONS__ || {})[staticId];

        if (htmlString) {
            var newDom = parseHtmlString(htmlString);
            _VirtualDom_adoptDomSubtree(newDom, tNode);
            return {
                __domNode: newDom,
                __translated: false,
                __reinsert: true  // Signal: insert this into document
            };
        }

        // Fall back to normal thunk evaluation
        y.__node = y.__thunk();
        return _VirtualDom_diffHelp(x.__node, y.__node, eventNode, tNode);
    }
}
```

### Helper: Adopt DOM Subtree

Build tNode tracking for adopted DOM (mini-virtualize):

```javascript
function _VirtualDom_adoptDomSubtree(domNode, tNode) {
    tNode.__domNode = domNode;

    if (domNode.nodeType === 1) {
        var dominated = 0;
        for (var child = domNode.firstChild; child; child = child.nextSibling) {
            if (child.nodeType === 1 && child.hasAttribute('data-elm')) {
                var childTNode = _VirtualDom_createTNode(undefined);
                tNode.__children[dominated] = childTNode;
                _VirtualDom_adoptDomSubtree(child, childTNode);
                dominated++;
            } else if (child.nodeType === 3) {
                // Text nodes
                var childTNode = _VirtualDom_createTNode(child);
                tNode.__children[dominated] = childTNode;
                dominated++;
            }
        }
    }
}
```

## Summary of Required Changes

### In elm-safe-virtual-dom

1. **Add adoption check** in `_VirtualDom_diffHelp` for type mismatches
2. **Add static region handling** in thunk comparison for SPA navigation
3. **Add `_VirtualDom_adoptDomSubtree`** helper (or expose existing virtualize internals)
4. **Optional**: A hook API so elm-pages can register its static region logic

### In elm-pages codemod

1. **Remove the DOM removal** (`parentNode.removeChild`) - this breaks virtualize
2. **Don't intercept on initial load** - let virtualize handle it
3. **Only handle SPA navigation** case (HTML string parsing)

## Alternative: Minimal Hook API

elm-safe-virtual-dom could expose a single hook point:

```javascript
// elm-pages registers at startup:
_VirtualDom_setAdoptionHook(function(oldVNode, newVNode, tNode) {
    // Return { domNode, alreadyInDocument } to adopt
    // Return null to use normal diffing
});
```

This keeps static-region-specific logic in elm-pages while elm-safe-virtual-dom just provides the adoption mechanism.
