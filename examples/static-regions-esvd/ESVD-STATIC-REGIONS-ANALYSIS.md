# Static Regions Compatibility with elm-safe-virtual-dom

## Overview

This document analyzes the compatibility challenges between elm-pages' "static regions" feature and elm-safe-virtual-dom (lydell's fork). The goal is to understand what changes would be needed to support static region adoption.

## What Static Regions Do

Static regions allow elm-pages to:
1. **Pre-render HTML at build time** (e.g., markdown, syntax-highlighted code)
2. **Ship that HTML in the initial page load** (for fast first paint)
3. **"Adopt" that pre-rendered DOM** on client-side hydration instead of re-rendering it
4. **On SPA navigation**: Parse HTML strings from `window.__ELM_PAGES_STATIC_REGIONS__` and inject them

This enables dead-code elimination - the heavy parsers (markdown, syntax highlighting) are only used at build time and don't ship to the client.

## How It Works in Standard virtual-dom

In standard elm/virtual-dom, we patch the thunk (lazy) rendering code:

```javascript
// Original thunk rendering:
if (tag === 5) {
    return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
}

// Patched version:
if (tag === 5) {
    // Check if this is a static region thunk
    if (vNode.l && vNode.l[1] && vNode.l[1].$ === 'StaticId') {
        var staticId = vNode.l[1].a;
        var existingDom = document.querySelector('[data-static="' + staticId + '"]');
        if (existingDom) {
            // Remove from document and adopt it
            existingDom.parentNode.removeChild(existingDom);
            // Set as the cached node so render returns it
            vNode.k = { $: 3, h: function() { return existingDom; }, ... };
        }
    }
    return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
}
```

This works in standard virtual-dom because `_VirtualDom_render` simply returns a DOM node, and that DOM node gets inserted into the document by the calling code.

## The elm-safe-virtual-dom Architecture

### The tNode System (lines 103-115 of VirtualDom.js)

elm-safe-virtual-dom introduces a **parallel tree structure** called `tNode`:

```javascript
// A `tNode`, or "tree node", is a tree structure that contains DOM nodes. The
// children are keyed by index for regular nodes, and by key for keyed nodes.
// This tree structure always matches the latest rendered virtual DOM tree,
// while the real DOM tree might have been modified by browser extensions, page
// translators and third party scripts. By using our own tree, we can guarantee
// access to the DOM nodes we need, even if someone else has changed the page.
function _VirtualDom_createTNode(domNode)
{
    return {
        __domNode: domNode,
        __children: Object.create(null)
    };
}
```

**Why it exists**: Browser extensions like Google Translate and Grammarly modify the DOM directly. They might:
- Replace text nodes with `<span>` elements containing translated text
- Insert extra elements into the DOM
- Remove elements entirely

When standard virtual-dom tries to diff/patch, it assumes the DOM matches its internal state. If an extension has modified the DOM, this assumption breaks and causes errors or visual glitches.

The tNode system solves this by maintaining its **own reference** to every DOM node it created, completely independent of the actual DOM tree structure.

### How Rendering Works (lines 556-623)

```javascript
function _VirtualDom_render(vNode, eventNode, tNode)
{
    // ... create DOM node ...

    // For element nodes with children:
    for (var kids = vNode.__kids, i = 0; i < kids.length; i++)
    {
        var childTNode = _VirtualDom_createTNode(undefined);  // Create child tNode
        var childDomNode = _VirtualDom_render(kids[i], eventNode, childTNode);
        tNode.__children[i] = childTNode;  // Store in parent's children
        _VirtualDom_appendChild(domNode, childDomNode);
    }

    tNode.__domNode = domNode;  // Store DOM reference in tNode
    return domNode;
}
```

Key points:
1. Each vNode gets a corresponding tNode
2. tNode stores the DOM node reference (`__domNode`)
3. tNode stores references to child tNodes (`__children`)
4. The tNode tree mirrors the vNode tree structure

### How Diffing/Patching Works

When virtual-dom needs to replace a node (REDRAW patch), it calls `_VirtualDom_applyPatchRedraw`:

```javascript
function _VirtualDom_applyPatchRedraw(x, y, eventNode, tNode)
{
    var domNode = tNode.__domNode;           // Get OLD DOM node from tNode
    var parentNode = domNode.parentNode;     // Get parent from OLD DOM
    var newNode = _VirtualDom_render(y, eventNode, tNode);  // Render NEW vNode

    if (parentNode)  // Replace old with new
    {
        parentNode.replaceChild(newNode, domNode);
        return { __domNode: newNode, __translated: ..., __reinsert: false };
    }
    else  // Extension removed our node - need to reinsert later
    {
        return { __domNode: newNode, __translated: ..., __reinsert: true };
    }
}
```

**Critical observation**: The function captures `domNode` and `parentNode` from the tNode **BEFORE** calling `_VirtualDom_render`.

## The Problem for Static Regions

### Scenario 1: Initial Page Load (DOM Adoption)

On initial page load:
1. Pre-rendered HTML exists in the document with `data-static="0"` attribute
2. Our patched thunk code detects the static region
3. We find the DOM node via `querySelector('[data-static="0"]')`
4. We try to make `_VirtualDom_render` return this pre-existing DOM node

**The problem**: The tNode for this thunk has `__domNode: undefined` (it's a fresh tNode). When we return our pre-existing DOM node:

1. The render succeeds and returns our DOM
2. But the tNode only gets updated with the new DOM reference at the end of render
3. In `_VirtualDom_applyPatchRedraw`, `domNode = tNode.__domNode` is `undefined`
4. Therefore `parentNode = undefined.parentNode` → `parentNode = undefined`
5. The `if (parentNode)` check fails
6. `replaceChild` is never called
7. Our DOM node is never inserted into the document

### Scenario 2: SPA Navigation

On SPA navigation:
1. We have HTML strings in `window.__ELM_PAGES_STATIC_REGIONS__`
2. Our patched thunk code parses the HTML string into a DOM node
3. Same problem as above - the newly created DOM never gets inserted

### Why Our Attempts Failed

We tried several approaches:

1. **Setting `tNode.__domNode`** before returning: Doesn't help because `applyPatchRedraw` captures it BEFORE calling render.

2. **Creating a custom node wrapper** (tag 3): The custom node's `__render` function is called, which returns our DOM. But we still have no parent reference to insert it.

3. **Copying tNode structure from virtualize**: We tried mimicking how `_VirtualDom_virtualize` sets up tNodes. But virtualize assumes it's processing existing DOM that's already in the document.

## What Would Need to Change

### Option A: Hook Before Render in applyPatchRedraw

The most minimal change would be a hook that runs BEFORE the render call in `applyPatchRedraw`:

```javascript
function _VirtualDom_applyPatchRedraw(x, y, eventNode, tNode)
{
    // NEW: Pre-render hook for static regions
    if (window.__ELM_PAGES_STATIC_REGION_HOOK__) {
        var hookResult = window.__ELM_PAGES_STATIC_REGION_HOOK__(y, tNode);
        if (hookResult) {
            // Hook handled it - returned the new DOM node
            tNode.__domNode = hookResult;
            // Still need parent for replacement...
        }
    }

    var domNode = tNode.__domNode;
    // ... rest of function
}
```

**Problem**: We still need a valid `domNode` to get `parentNode` from. The hook would need to also provide parent info somehow.

### Option B: Parent-Aware Render

Pass parent information down through the render tree:

```javascript
function _VirtualDom_render(vNode, eventNode, tNode, parentTNode, index)
{
    // Now we know our parent and our index in parent's children
    // For static regions, we could:
    // 1. Get the parent's DOM node: parentTNode.__domNode
    // 2. Insert our adopted DOM at the correct position
}
```

**Problem**: Significant API change throughout the rendering system.

### Option C: Virtualize-Based Adoption

Add support for "adopting" pre-existing DOM subtrees into the tNode tree:

```javascript
function _VirtualDom_adoptDom(domNode, parentTNode, index) {
    // Create a tNode for the adopted DOM
    var tNode = _VirtualDom_createTNode(domNode);
    parentTNode.__children[index] = tNode;

    // Recursively create tNodes for children
    // (similar to _VirtualDom_virtualize but for a specific subtree)
    return tNode;
}
```

This would need to be called when we detect a static region thunk, but we'd need access to the parent tNode.

### Option D: Custom Static Region vNode Type

Introduce a new vNode type specifically for static regions:

```javascript
// New vNode type: STATIC_REGION = 6
// Has: staticId, fallbackThunk
// render() finds or creates DOM from static content
// diffHelp() has special handling for adoption
```

This is the most comprehensive solution but requires the most changes.

## Recommendation for Discussion

The cleanest solution would likely be **Option C** - a mechanism to "adopt" a DOM subtree. This fits well with elm-safe-virtual-dom's philosophy:

1. **It's about DOM node tracking**: The tNode system exists to track DOM nodes reliably. Adopting pre-existing DOM is conceptually similar to virtualization.

2. **It's declarative**: Rather than patching internal functions, we'd have an explicit API for adoption.

3. **It could be useful beyond elm-pages**: Any SSR/hydration scenario could benefit from this.

The key insight is that `_VirtualDom_virtualize` already does something similar - it takes existing DOM and creates the corresponding vNode + tNode structure. We need a variant that:
- Works for a subtree (not the whole app)
- Can be triggered during render/diff (not just at initialization)
- Integrates with the patch application system

## Minimal Questions for Simon

1. Is there a way to "adopt" a DOM node into the tNode tree during render, given we don't have access to the parent tNode?

2. Would you consider adding a hook or callback in `_VirtualDom_applyPatchRedraw` that could provide an alternative DOM node before the render call?

3. Or is there a different approach you'd recommend for SSR hydration scenarios where pre-rendered DOM needs to be adopted rather than re-rendered?
