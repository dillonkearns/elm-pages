/**
 * Static Region Codemod for elm-safe-virtual-dom (lydell's fork)
 *
 * This version works WITH elm-safe-virtual-dom's virtualize mechanism rather than against it.
 *
 * Key insight: elm-safe-virtual-dom already adopts server-rendered HTML through its virtualize
 * function at app startup. The tNode system tracks DOM nodes independently of the actual DOM tree
 * to handle browser extension modifications (Google Translate, Grammarly, etc.).
 *
 * Our approach:
 * 1. Initial page load: virtualize has already adopted the DOM and built the tNode tree.
 *    When diffing sees virtualized-node vs static-region-thunk, we check if the DOM has
 *    a matching data-static attribute and keep it without evaluating the thunk.
 *
 * 2. Re-renders (counter clicks, etc.): thunk-vs-thunk with same static ID.
 *    We keep the existing DOM from tNode.r.
 *
 * 3. SPA navigation: thunk-vs-thunk with different static IDs.
 *    Parse HTML from window.__ELM_PAGES_STATIC_REGIONS__ and use __reinsert flag.
 *
 * See: tnode-explainer.md and proposed-esvd-design.md for detailed architecture notes.
 */

/**
 * Patch for the "old is not thunk, new is thunk" case in diffHelp.
 * This handles initial page load where virtualize has already adopted the DOM.
 *
 * Original:
 *   if (y.$ === 5) {
 *       return _VirtualDom_diffHelp(x, y.k || (y.k = y.m()), eventNode, tNode);
 *   }
 *
 * We intercept to check: if the new thunk is a static region, and the existing DOM
 * (from virtualize) has a matching data-static attribute, keep it without evaluating the thunk.
 */
const STATIC_REGION_VIRTUALIZE_ADOPTION = `
    // Static region adoption: check if new thunk is for a static region
    var __yRefs = y.l;
    var __isStaticRegion = __yRefs && __yRefs.length >= 2 && __yRefs[1] &&
        (__yRefs[1].$ === 'StaticId' || __yRefs[1].$ === 0) &&
        typeof __yRefs[1].a === 'string';

    if (__isStaticRegion) {
        var __staticId = __yRefs[1].a;
        var __existingDom = tNode.r;  // DOM from virtualize

        // Check if existing DOM has matching data-static attribute
        if (__existingDom && __existingDom.nodeType === 1) {
            var __existingStaticId = __existingDom.getAttribute('data-static');
            if (__existingStaticId === __staticId) {
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
 * 2. SPA navigation: Need HTML from window.__ELM_PAGES_STATIC_REGIONS__
 *    → Parse HTML, return with reinsert flag
 */
const STATIC_REGION_SPA_NAVIGATION = `
    // Static region: check if this is a static region thunk
    var __yIsStatic = yRefs && yRefs.length >= 2 && yRefs[1] &&
        (yRefs[1].$ === 'StaticId' || yRefs[1].$ === 0);
    var __xIsStatic = xRefs && xRefs.length >= 2 && xRefs[1] &&
        (xRefs[1].$ === 'StaticId' || xRefs[1].$ === 0);

    if (__yIsStatic && __xIsStatic) {
        var __newStaticId = yRefs[1].a;
        var __oldStaticId = xRefs[1].a;

        // Case 1: Same static region, re-render after adoption
        // x.k is undefined because we adopted without evaluating
        if (__newStaticId === __oldStaticId) {
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

        // Case 2: Different static region (SPA navigation)
        var __globalContent = (window.__ELM_PAGES_STATIC_REGIONS__ || {})[__newStaticId];

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
export function patchStaticRegionsESVD(elmCode) {
    let patchedCode = elmCode;
    let patchCount = 0;

    // Patch 1: "old is not thunk, new is thunk" case
    // This handles initial page load where virtualize has adopted the DOM
    // Pattern: if (y.$ === 5) { return _VirtualDom_diffHelp(x, y.k || (y.k = y.m()), eventNode, tNode); }
    const virtualizePatchPattern = /(if\s*\(\s*y\.\$\s*===\s*5\s*\)\s*\{)\s*(return\s+_VirtualDom_diffHelp\s*\(\s*x\s*,\s*y\.k\s*\|\|\s*\(\s*y\.k\s*=\s*y\.m\s*\(\s*\)\s*\)\s*,\s*eventNode\s*,\s*tNode\s*\))/;

    if (virtualizePatchPattern.test(patchedCode)) {
        patchedCode = patchedCode.replace(virtualizePatchPattern,
            `$1${STATIC_REGION_VIRTUALIZE_ADOPTION}
    $2`
        );
        patchCount++;
    } else {
        console.warn('[static-region-codemod-esvd] Could not find virtualize adoption patch point');
    }

    // Patch 2: thunk-vs-thunk comparison for SPA navigation and re-renders
    // Pattern: after the refs comparison loop, before y.k = y.m()
    const spaNavigationPattern = /(var\s+xRefs\s*=\s*x\.l\s*;\s*var\s+yRefs\s*=\s*y\.l\s*;[\s\S]*?while\s*\(\s*same\s*&&\s*i\s*--\s*\)\s*\{[\s\S]*?\}\s*if\s*\(\s*same\s*\)\s*\{[\s\S]*?\})\s*(y\.k\s*=\s*y\.m\s*\(\s*\)\s*;)/;

    if (spaNavigationPattern.test(patchedCode)) {
        patchedCode = patchedCode.replace(spaNavigationPattern,
            `$1
                ${STATIC_REGION_SPA_NAVIGATION}
                $2`
        );
        patchCount++;
    } else {
        console.warn('[static-region-codemod-esvd] Could not find SPA navigation patch point');
    }

    if (patchCount === 2) {
        console.log('[static-region-codemod-esvd] Successfully applied 2 patches for elm-safe-virtual-dom');
    } else {
        console.warn(`[static-region-codemod-esvd] Only applied ${patchCount}/2 patches`);
    }

    return patchedCode;
}

export default { patchStaticRegionsESVD };
