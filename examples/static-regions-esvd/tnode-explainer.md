# The tNode System Explained Simply

## The Problem tNode Solves

Browser extensions like Google Translate and Grammarly directly modify your webpage's HTML. For example, Google Translate might:

1. Find a text node containing "Hello"
2. Delete it
3. Replace it with `<span class="translated">Bonjour</span>`

Standard virtual-dom assumes **it controls the DOM**. When it tries to update "Hello" to "Hello!" later, it looks for that text node - but it's gone. The extension deleted it. This causes crashes or visual glitches.

## How tNode Works

elm-safe-virtual-dom keeps its **own private record** of every DOM node it created:

```
tNode tree (elm's private record)     Actual DOM (what browser shows)
─────────────────────────────────     ─────────────────────────────────
tNode
  ├─ __domNode: <div>  ───────────►   <div>
  └─ __children:                        ├─ <span class="translated">  ← extension added this
      ├─ [0]: tNode                     │    └─ "Bonjour"
      │    └─ __domNode: "Hello" ──►    │        (our node is gone from DOM!)
      └─ [1]: tNode                     └─ <p>
           └─ __domNode: <p>  ─────►        └─ "World"
```

Even though the extension removed "Hello" from the DOM, **elm still has a reference to it** in the tNode tree. When elm needs to update that text node, it uses its saved reference instead of searching the (now-modified) DOM.

## How Virtual-DOM Updates Work

When you change something in your Elm view:

1. **Diff**: Compare old vNode tree with new vNode tree
2. **Patch**: For each difference, update the DOM

In standard virtual-dom, patching a node replacement looks like:
```javascript
// Find parent, replace old with new
oldDomNode.parentNode.replaceChild(newDomNode, oldDomNode);
```

In elm-safe-virtual-dom, it's:
```javascript
// Get our saved reference to the old node
var oldDomNode = tNode.__domNode;
var parentNode = oldDomNode.parentNode;
// Replace old with new
parentNode.replaceChild(newDomNode, oldDomNode);
// Save reference to new node
tNode.__domNode = newDomNode;
```

The key difference: **elm-safe-virtual-dom looks up the old DOM node from its private tNode record BEFORE doing anything else.**

## Why This Breaks Static Region Adoption

Our static region technique works like this:

1. Server renders HTML with `<div data-static="0">...content...</div>`
2. Browser loads page - that HTML is already in the DOM
3. Elm starts up, virtual-dom begins rendering
4. When it hits our static region thunk, we intercept and say "don't render this - just use that existing DOM node over there"

**In standard virtual-dom**, this works because we just return a DOM node and it gets used.

**In elm-safe-virtual-dom**, when it's time to insert our adopted DOM node:

```javascript
function _VirtualDom_applyPatchRedraw(x, y, eventNode, tNode) {
    var domNode = tNode.__domNode;        // ← Gets undefined (no saved reference yet!)
    var parentNode = domNode.parentNode;  // ← undefined.parentNode = undefined
    var newNode = _VirtualDom_render(...); // ← We return our adopted DOM here

    if (parentNode) {                     // ← FALSE! parentNode is undefined
        parentNode.replaceChild(newNode, domNode);  // ← Never runs!
    }
}
```

The tNode for our static region has `__domNode: undefined` because elm never created a DOM node for it before - we're trying to adopt pre-existing HTML. With no saved reference, there's no parent to insert into.

## The Core Conflict

| Standard virtual-dom | elm-safe-virtual-dom |
|---------------------|---------------------|
| "Here's a DOM node, put it in the document" | "I need to find the OLD node first so I know WHERE to put the new one" |
| Works with any DOM node | Requires elm to have created the previous node |

Our adoption technique assumes we can hand virtual-dom a DOM node and it will figure out where to put it. But elm-safe-virtual-dom's safety mechanism requires knowing the previous node's location first - and for adopted HTML, there is no "previous node" in elm's records.
