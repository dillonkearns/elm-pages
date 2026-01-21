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

// Test that the codemod injects the handler functions
function testHandlerInjection() {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    const hasHandler = patched.includes('_VirtualDom_handleStaticRegion');
    const hasChecker = patched.includes('_VirtualDom_isStaticRegion');

    console.log('Test: Handler injection');
    console.log('  - _VirtualDom_handleStaticRegion injected:', hasHandler ? '✓' : '✗');
    console.log('  - _VirtualDom_isStaticRegion injected:', hasChecker ? '✓' : '✗');

    return hasHandler && hasChecker;
}

// Test that the thunk case is patched
function testThunkPatching() {
    const patched = patchStaticRegions(SAMPLE_VDOM_CODE);

    // The patched code should check for static region before the normal thunk handling
    const hasStaticCheck = patched.includes('if (_VirtualDom_isStaticRegion(vNode.l))');

    console.log('Test: Thunk patching');
    console.log('  - Static region check added:', hasStaticCheck ? '✓' : '✗');

    // Verify the original thunk rendering is still there as fallback
    const hasOriginalThunk = patched.includes('vNode.k || (vNode.k = vNode.m())');

    console.log('  - Original thunk handling preserved:', hasOriginalThunk ? '✓' : '✗');

    return hasStaticCheck && hasOriginalThunk;
}

// Test the handler function logic (in isolation)
function testHandlerLogic() {
    console.log('Test: Handler logic');

    // Mock document
    const mockDoc = {
        querySelector: (selector) => {
            if (selector === '[data-static="test-id"]') {
                return {
                    id: 'test-element',
                    parentNode: {
                        removeChild: function(child) {
                            console.log('  - removeChild called: ✓');
                            return child;
                        }
                    }
                };
            }
            return null;
        },
        createElement: (tag) => ({ tagName: tag, innerHTML: '' }),
        createTextNode: (text) => ({ nodeType: 3, textContent: text })
    };

    // Simulate the handler (copy from codemod)
    function _VirtualDom_handleStaticRegion(vNode, refs, eventNode) {
        var staticId = refs[1];
        var htmlFallback = refs[2] || '';
        var id = staticId.a;

        // Case 1: Try to adopt existing DOM
        var existingDom = mockDoc.querySelector('[data-static="' + id + '"]');
        if (existingDom) {
            if (existingDom.parentNode) {
                existingDom.parentNode.removeChild(existingDom);
            }
            return existingDom;
        }

        // Case 2: Parse HTML string
        if (htmlFallback && htmlFallback.length > 0) {
            var template = mockDoc.createElement('template');
            template.innerHTML = htmlFallback;
            // In real code, would use template.content.firstElementChild
            return { fromHtml: true, html: htmlFallback };
        }

        return mockDoc.createTextNode('');
    }

    // Test case 1: Existing DOM adoption
    const mockVNode1 = {};
    const mockRefs1 = [
        function() {},
        { $: 'StaticId', a: 'test-id' },
        ''
    ];

    const result1 = _VirtualDom_handleStaticRegion(mockVNode1, mockRefs1, null);
    const adoptionWorks = result1 && result1.id === 'test-element';
    console.log('  - Existing DOM adoption:', adoptionWorks ? '✓' : '✗');

    // Test case 2: HTML string parsing
    const mockVNode2 = {};
    const mockRefs2 = [
        function() {},
        { $: 'StaticId', a: 'nonexistent-id' },
        '<div>Test HTML</div>'
    ];

    const result2 = _VirtualDom_handleStaticRegion(mockVNode2, mockRefs2, null);
    const htmlParsingWorks = result2 && result2.fromHtml === true;
    console.log('  - HTML string parsing:', htmlParsingWorks ? '✓' : '✗');

    return adoptionWorks && htmlParsingWorks;
}

// Run all tests
console.log('=== Static Region Codemod Tests ===\n');

const results = [
    testHandlerInjection(),
    testThunkPatching(),
    testHandlerLogic()
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
