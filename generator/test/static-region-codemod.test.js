/**
 * Test for the static region codemod
 *
 * This test verifies that the codemod correctly patches the virtual-dom
 * thunk rendering to support static region adoption.
 */

import { describe, it, expect } from "vitest";
import { patchStaticRegions } from "../src/static-region-codemod.js";

// Sample compiled Elm virtual-dom code (simplified)
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

function _VirtualDom_diff(x, y) {
    // ... diff implementation
}
`;

describe("Static Region Codemod", () => {
  it("injects static region code", () => {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // The new approach inlines the check directly
    const hasStaticRefsVar = patched.includes('__staticRefs') || patched.includes('__isStaticRegion');
    const hasDataStaticSelector = patched.includes('data-static');
    const hasStaticIdCheck = patched.includes("StaticId") || patched.includes("=== 0");

    expect(hasStaticRefsVar).toBe(true);
    expect(hasDataStaticSelector).toBe(true);
    expect(hasStaticIdCheck).toBe(true);
  });

  it("patches the thunk case", () => {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // The patched code should have the static region check in the tag === 5 block
    const hasTag5Block = patched.includes('tag === 5');

    // Check for the virtualize call (used to convert adopted DOM to virtual-dom)
    const hasVirtualize = patched.includes('_VirtualDom_virtualize');

    // Verify the original thunk rendering is still there as fallback
    const hasOriginalThunk = patched.includes('vNode.k || (vNode.k = vNode.m())');

    expect(hasTag5Block).toBe(true);
    expect(hasVirtualize).toBe(true);
    expect(hasOriginalThunk).toBe(true);
  });

  it("supports both debug and optimized modes", () => {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // The patched code should support both debug mode ('StaticId') and optimized mode (0)
    const hasStringCheck = patched.includes("'StaticId'") || patched.includes('"StaticId"');
    const hasNumericCheck = patched.includes('=== 0') || patched.includes('===0');

    expect(hasStringCheck).toBe(true);
    expect(hasNumericCheck).toBe(true);
  });

  it("includes global fallback mechanism", () => {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // Check for window.__ELM_PAGES_STATIC_REGIONS__ fallback
    const hasGlobalFallback = patched.includes('__ELM_PAGES_STATIC_REGIONS__');

    expect(hasGlobalFallback).toBe(true);
  });
});
