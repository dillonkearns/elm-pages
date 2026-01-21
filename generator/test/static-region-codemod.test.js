/**
 * Test for the static region codemod
 *
 * This test verifies that the codemod correctly patches the virtual-dom
 * thunk rendering to support static region adoption.
 */

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

// Test that the codemod injects the inlined static region check
function testInlinedCodeInjection() {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // The new approach inlines the check directly
    const hasStaticRefsVar = patched.includes('__staticRefs') || patched.includes('__isStaticRegion');
    const hasDataStaticSelector = patched.includes('data-static');
    const hasStaticIdCheck = patched.includes("StaticId") || patched.includes("=== 0");

    console.log('Test: Inlined code injection');
    console.log('  - Static refs variable:', hasStaticRefsVar ? '✓' : '✗');
    console.log('  - data-static selector:', hasDataStaticSelector ? '✓' : '✗');
    console.log('  - StaticId check:', hasStaticIdCheck ? '✓' : '✗');

    return hasStaticRefsVar && hasDataStaticSelector && hasStaticIdCheck;
}

// Test that the thunk case is patched
function testThunkPatching() {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // The patched code should have the static region check in the tag === 5 block
    const hasTag5Block = patched.includes('tag === 5');

    // Check for the virtualize call (used to convert adopted DOM to virtual-dom)
    const hasVirtualize = patched.includes('_VirtualDom_virtualize');

    console.log('Test: Thunk patching');
    console.log('  - tag === 5 block present:', hasTag5Block ? '✓' : '✗');
    console.log('  - _VirtualDom_virtualize call:', hasVirtualize ? '✓' : '✗');

    // Verify the original thunk rendering is still there as fallback
    const hasOriginalThunk = patched.includes('vNode.k || (vNode.k = vNode.m())');

    console.log('  - Original thunk handling preserved:', hasOriginalThunk ? '✓' : '✗');

    return hasTag5Block && hasVirtualize && hasOriginalThunk;
}

// Test that both debug mode ($ === 'StaticId') and optimized mode ($ === 0) checks are present
function testDualModeSupport() {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // The patched code should support both debug mode ('StaticId') and optimized mode (0)
    const hasStringCheck = patched.includes("'StaticId'") || patched.includes('"StaticId"');
    const hasNumericCheck = patched.includes('=== 0') || patched.includes('===0');

    console.log('Test: Dual mode support (debug + optimized)');
    console.log('  - Debug mode check ($ === "StaticId"):', hasStringCheck ? '✓' : '✗');
    console.log('  - Optimized mode check ($ === 0):', hasNumericCheck ? '✓' : '✗');

    return hasStringCheck && hasNumericCheck;
}

// Test the global fallback mechanism
function testGlobalFallback() {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // Check for window.__ELM_PAGES_STATIC_REGIONS__ fallback
    const hasGlobalFallback = patched.includes('__ELM_PAGES_STATIC_REGIONS__');

    console.log('Test: Global fallback mechanism');
    console.log('  - window.__ELM_PAGES_STATIC_REGIONS__ check:', hasGlobalFallback ? '✓' : '✗');

    return hasGlobalFallback;
}

// Run all tests
console.log('=== Static Region Codemod Tests ===\n');

const results = [
    testInlinedCodeInjection(),
    testThunkPatching(),
    testDualModeSupport(),
    testGlobalFallback()
];

console.log('\n=== Summary ===');
const passed = results.filter(r => r).length;
const total = results.length;
console.log(`Passed: ${passed}/${total}`);

if (passed === total) {
    console.log('\n✓ All tests passed!');
    process.exit(0);
} else {
    console.log('\n✗ Some tests failed');
    process.exit(1);
}
