/**
 * Frozen View Codemod for elm-safe-virtual-dom (lydell's fork)
 *
 * This version works WITH elm-safe-virtual-dom's virtualize mechanism rather than against it.
 *
 * Key insight: elm-safe-virtual-dom already adopts server-rendered HTML through its virtualize
 * function at app startup. The tNode system tracks DOM nodes independently of the actual DOM tree
 * to handle browser extension modifications (Google Translate, Grammarly, etc.).
 *
 * Our approach:
 * 1. Initial page load: virtualize has already adopted the DOM and built the tNode tree.
 *    When diffing sees virtualized-node vs frozen-view-thunk, we check if the DOM has
 *    a matching data-static attribute and keep it without evaluating the thunk.
 *
 * 2. Re-renders (counter clicks, etc.): thunk-vs-thunk with same frozen view ID.
 *    We keep the existing DOM from tNode.r.
 *
 * 3. SPA navigation: thunk-vs-thunk with different frozen view IDs.
 *    Parse HTML from window.__ELM_PAGES_FROZEN_VIEWS__ and use __reinsert flag.
 *
 * Detection uses a magic string prefix "__ELM_PAGES_STATIC__" instead of a custom type,
 * which is more robust because strings survive minification unchanged.
 *
 * See: tnode-explainer.md and proposed-esvd-design.md for detailed architecture notes.
 */

// Magic prefix for frozen view identification
const FROZEN_VIEW_PREFIX = '__ELM_PAGES_STATIC__';
const FROZEN_VIEW_PREFIX_LENGTH = FROZEN_VIEW_PREFIX.length; // 21

/**
 * Patch for the "old is not thunk, new is thunk" case in diffHelp.
 * This handles initial page load where virtualize has already adopted the DOM.
 *
 * Original:
 *   if (y.$ === 5) {
 *       return _VirtualDom_diffHelp(x, y.k || (y.k = y.m()), eventNode, tNode);
 *   }
 *
 * We intercept to check: if the new thunk is a frozen view, and the existing DOM
 * (from virtualize) has a matching data-static attribute, keep it without evaluating the thunk.
 */
const FROZEN_VIEW_VIRTUALIZE_ADOPTION = `
    // Frozen view adoption: check if new thunk is for a frozen view
    // Detection: refs[1] is a string starting with "__ELM_PAGES_STATIC__"
    var __yRefs = y.l;
    var __isFrozenView = __yRefs && __yRefs.length >= 2 &&
        typeof __yRefs[1] === 'string' &&
        __yRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');

    if (__isFrozenView) {
        var __frozenId = __yRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH});
        var __existingDom = tNode.r;  // DOM from virtualize

        // Check if existing DOM has matching data-static attribute
        if (__existingDom && __existingDom.nodeType === 1) {
            var __existingFrozenId = __existingDom.getAttribute('data-static');
            if (__existingFrozenId === __frozenId) {
                // Keep the existing DOM - don't evaluate thunk!
                return {
                    r: __existingDom,
                    u: false,
                    v: false
                };
            }
        }
    }
`;

/**
 * Patch for thunk-vs-thunk comparison (SPA navigation AND re-renders after adoption).
 *
 * Cases handled:
 * 1. Re-render after adoption: x.k is undefined but tNode.r has the adopted DOM
 *    → Keep existing DOM, don't evaluate thunk
 * 2. SPA navigation: Need HTML from window.__ELM_PAGES_FROZEN_VIEWS__
 *    → Parse HTML, return with reinsert flag
 */
const FROZEN_VIEW_SPA_NAVIGATION = `
    // Frozen view: check if this is a frozen view thunk
    // Detection: refs[1] is a string starting with "__ELM_PAGES_STATIC__"
    var __yIsFrozen = yRefs && yRefs.length >= 2 && typeof yRefs[1] === 'string' && yRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');
    var __xIsFrozen = xRefs && xRefs.length >= 2 && typeof xRefs[1] === 'string' && xRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');

    if (__yIsFrozen && __xIsFrozen) {
        var __newFrozenId = yRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH});
        var __oldFrozenId = xRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH});

        // Case 1: Same frozen view, re-render after adoption
        // x.k is undefined because we adopted without evaluating
        if (__newFrozenId === __oldFrozenId) {
            var __existingDom = tNode.r;
            if (__existingDom && __existingDom.nodeType === 1) {
                // Keep existing DOM, skip thunk evaluation
                return {
                    r: __existingDom,
                    u: false,
                    v: false
                };
            }
        }

        // Case 2: Different frozen view (SPA navigation)
        var __globalContent = (window.__ELM_PAGES_FROZEN_VIEWS__ || {})[__newFrozenId];

        if (__globalContent && __globalContent.length > 0) {
            // Parse HTML string into DOM
            var __template = document.createElement('template');
            __template.innerHTML = __globalContent;
            var __newDom = __template.content.firstElementChild;

            if (__newDom) {
                // Set tNode to track the new DOM
                tNode.r = __newDom;
                tNode.s = Object.create(null);

                // Return with reinsert flag - elm-safe-virtual-dom will handle insertion
                return {
                    r: __newDom,
                    u: false,
                    v: true  // __reinsert: true - needs to be inserted into document
                };
            }
        }
    }
`;

/**
 * Patches the compiled Elm output for elm-safe-virtual-dom compatibility.
 *
 * @param {string} elmCode - The compiled Elm JavaScript code
 * @returns {string} - The patched code
 */
export function patchFrozenViewsESVD(elmCode) {
    let patchedCode = elmCode;
    let patchCount = 0;

    // Patch 1: "old is not thunk, new is thunk" case
    // This handles initial page load where virtualize has adopted the DOM
    // Pattern: if (y.$ === 5) { return _VirtualDom_diffHelp(x, y.k || (y.k = y.m()), eventNode, tNode); }
    const virtualizePatchPattern = /(if\s*\(\s*y\.\$\s*===\s*5\s*\)\s*\{)\s*(return\s+_VirtualDom_diffHelp\s*\(\s*x\s*,\s*y\.k\s*\|\|\s*\(\s*y\.k\s*=\s*y\.m\s*\(\s*\)\s*\)\s*,\s*eventNode\s*,\s*tNode\s*\))/;

    if (virtualizePatchPattern.test(patchedCode)) {
        patchedCode = patchedCode.replace(virtualizePatchPattern,
            `$1${FROZEN_VIEW_VIRTUALIZE_ADOPTION}
    $2`
        );
        patchCount++;
    }

    // Patch 2: thunk-vs-thunk comparison for SPA navigation and re-renders
    // Pattern: after the refs comparison loop, before y.k = y.m()
    const spaNavigationPattern = /(var\s+xRefs\s*=\s*x\.l\s*;\s*var\s+yRefs\s*=\s*y\.l\s*;[\s\S]*?while\s*\(\s*same\s*&&\s*i\s*--\s*\)\s*\{[\s\S]*?\}\s*if\s*\(\s*same\s*\)\s*\{[\s\S]*?\})\s*(y\.k\s*=\s*y\.m\s*\(\s*\)\s*;)/;

    if (spaNavigationPattern.test(patchedCode)) {
        patchedCode = patchedCode.replace(spaNavigationPattern,
            `$1
                ${FROZEN_VIEW_SPA_NAVIGATION}
                $2`
        );
        patchCount++;
    }

    if (patchCount < 2) {
        throw new Error(`[frozen-view-codemod-esvd] Only applied ${patchCount}/2 patches - elm-safe-virtual-dom structure may have changed`);
    }

    return patchedCode;
}

export default { patchFrozenViewsESVD };
