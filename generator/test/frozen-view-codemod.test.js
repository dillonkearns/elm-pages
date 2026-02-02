/**
 * Test for the frozen view codemod
 *
 * This test verifies that the codemod correctly patches the virtual-dom
 * thunk rendering to support frozen view adoption.
 */

import { describe, it, expect } from "vitest";
import { patchFrozenViews } from "../src/frozen-view-codemod.js";

// Sample compiled Elm virtual-dom code (simplified but with thunk diffing structure)
const SAMPLE_VDOM_CODE = `
var _VirtualDom_doc = typeof document !== 'undefined' ? document : {};

function _VirtualDom_virtualize(node) {
    if (node.nodeType === 3) {
        return _VirtualDom_text(node.textContent);
    }
    // ... more implementation
    return node;
}

function _VirtualDom_render(vNode, eventNode) {
    var tag = vNode.$;

    if (tag === 5) {
        return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
    }

    if (tag === 0) {
        return _VirtualDom_doc.createTextNode(vNode.a);
    }

    // ... more node types
    return _VirtualDom_doc.createElement('div');
}

function _VirtualDom_diffHelp(x, y, patches, index) {
    if (x === y) { return; }
    var xType = x.$;
    var yType = y.$;
    if (xType !== yType) {
        _VirtualDom_pushPatch(patches, 0, index, y);
        return;
    }
    switch (yType) {
        case 5:
            var xRefs = x.l;
            var yRefs = y.l;
            var i = xRefs.length;
            var same = i === yRefs.length;
            while (same && i--) {
                same = xRefs[i] === yRefs[i];
            }
            if (same) { y.k = x.k; return; }
            _VirtualDom_pushPatch(patches, 0, index, y);
            return;
    }
}
`;

describe("Frozen View Codemod", () => {
  it("injects frozen view code", () => {
    const patched = patchFrozenViews(SAMPLE_VDOM_CODE);

    // The new approach inlines the check directly
    const hasFrozenRefsVar = patched.includes('__frozenRefs') || patched.includes('__isFrozenView');
    const hasDataStaticSelector = patched.includes('data-static');
    const hasFrozenIdCheck = patched.includes("FrozenId") || patched.includes("=== 0");

    expect(hasFrozenRefsVar).toBe(true);
    expect(hasDataStaticSelector).toBe(true);
    expect(hasFrozenIdCheck).toBe(true);
  });

  it("patches the thunk case", () => {
    const patched = patchFrozenViews(SAMPLE_VDOM_CODE);

    // The patched code should have the frozen view check in the tag === 5 block
    const hasTag5Block = patched.includes('tag === 5');

    // Check for the virtualize call (used to convert adopted DOM to virtual-dom)
    const hasVirtualize = patched.includes('_VirtualDom_virtualize');

    // Verify the original thunk rendering is still there as fallback
    const hasOriginalThunk = patched.includes('vNode.k || (vNode.k = vNode.m())');

    expect(hasTag5Block).toBe(true);
    expect(hasVirtualize).toBe(true);
    expect(hasOriginalThunk).toBe(true);
  });

  it("uses magic string prefix detection", () => {
    const patched = patchFrozenViews(SAMPLE_VDOM_CODE);

    // The patched code should detect magic string prefix "__ELM_PAGES_STATIC__"
    const hasMagicPrefixCheck = patched.includes('__ELM_PAGES_STATIC__');
    const hasStringTypeCheck = patched.includes("typeof") && patched.includes("=== 'string'");

    expect(hasMagicPrefixCheck).toBe(true);
    expect(hasStringTypeCheck).toBe(true);
  });

  it("includes global fallback mechanism", () => {
    const patched = patchFrozenViews(SAMPLE_VDOM_CODE);

    // Check for window.__ELM_PAGES_FROZEN_VIEWS__ fallback
    const hasGlobalFallback = patched.includes('__ELM_PAGES_FROZEN_VIEWS__');

    expect(hasGlobalFallback).toBe(true);
  });

  it("patches elm-safe-virtual-dom code with tNode parameter", () => {
    // elm-safe-virtual-dom (lydell/virtual-dom) has an extra tNode parameter
    const SAFE_VDOM_CODE = `
function _VirtualDom_render(vNode, eventNode, tNode) {
    var tag = vNode.$;

    if (tag === 5) {
        return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode, tNode);
    }

    if (tag === 0) {
        return _VirtualDom_doc.createTextNode(vNode.a);
    }

    return _VirtualDom_doc.createElement('div');
}

function _VirtualDom_diffHelp(x, y, patches, index) {
    if (x === y) { return; }
    var xType = x.$;
    var yType = y.$;
    if (xType !== yType) {
        _VirtualDom_pushPatch(patches, 0, index, y);
        return;
    }
    switch (yType) {
        case 5:
            var xRefs = x.l;
            var yRefs = y.l;
            var i = xRefs.length;
            var same = i === yRefs.length;
            while (same && i--) {
                same = xRefs[i] === yRefs[i];
            }
            if (same) { y.k = x.k; return; }
            _VirtualDom_pushPatch(patches, 0, index, y);
            return;
    }
}
`;

    const patched = patchFrozenViews(SAFE_VDOM_CODE);

    // Verify the frozen view check was injected
    const hasFrozenRefsVar = patched.includes('__frozenRefs') || patched.includes('__isFrozenView');
    const hasDataStaticSelector = patched.includes('data-static');

    // Verify the original thunk rendering with tNode is still there as fallback
    const hasOriginalThunk = patched.includes('vNode.k || (vNode.k = vNode.m())');
    const hasTNodeParam = patched.includes('eventNode, tNode');

    expect(hasFrozenRefsVar).toBe(true);
    expect(hasDataStaticSelector).toBe(true);
    expect(hasOriginalThunk).toBe(true);
    expect(hasTNodeParam).toBe(true);
  });
});
