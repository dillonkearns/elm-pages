/**
 * Static Region Codemod for elm-safe-virtual-dom
 *
 * This version works WITH elm-safe-virtual-dom's virtualize mechanism rather than against it.
 *
 * Key insight: elm-safe-virtual-dom already adopts server-rendered HTML through virtualize.
 * We just need to prevent the thunk from being evaluated when there's matching DOM.
 *
 * Hook points:
 * 1. When diffing: old node (virtualized) vs new thunk → check if DOM has matching data-static
 * 2. When diffing: old thunk vs new thunk (SPA navigation) → use HTML from global
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
                console.log('[StaticRegion] Adopting virtualized DOM for', __staticId);
                // Keep the existing DOM - don't evaluate thunk!
                // Return success with the existing DOM node
                return {
                    r: __existingDom,
                    u: false,
                    v: false
                };
            }
        }
        console.log('[StaticRegion] No matching virtualized DOM for', __staticId, ', evaluating thunk');
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
                console.log('[StaticRegion] Re-render: keeping adopted DOM for', __newStaticId);
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
            console.log('[StaticRegion] SPA navigation: using HTML from global for', __newStaticId);

            // Parse HTML string into DOM
            var __template = document.createElement('template');
            __template.innerHTML = __globalContent;
            var __newDom = __template.content.firstElementChild;

            if (__newDom) {
                // Set tNode to track the new DOM
                tNode.r = __newDom;
                // Build children tracking (simplified - just mark as needing full tracking)
                tNode.s = Object.create(null);

                // Return with reinsert flag - elm-safe-virtual-dom will handle insertion
                return {
                    r: __newDom,
                    u: false,
                    v: true  // __reinsert: true - needs to be inserted into document
                };
            }
        }
        console.log('[StaticRegion] No global HTML for', __newStaticId, ', evaluating thunk');
    }
`;

/**
 * Patches the compiled Elm output for elm-safe-virtual-dom compatibility.
 */
export function patchStaticRegionsESVD(elmCode) {
    let patchedCode = elmCode;
    let patchCount = 0;

    // Patch 1: "old is not thunk, new is thunk" case
    // Pattern: if (y.$ === 5) { return _VirtualDom_diffHelp(x, y.k || (y.k = y.m()), eventNode, tNode); }
    const virtualizePatchPattern = /(if\s*\(\s*y\.\$\s*===\s*5\s*\)\s*\{)\s*(return\s+_VirtualDom_diffHelp\s*\(\s*x\s*,\s*y\.k\s*\|\|\s*\(\s*y\.k\s*=\s*y\.m\s*\(\s*\)\s*\)\s*,\s*eventNode\s*,\s*tNode\s*\))/;

    if (virtualizePatchPattern.test(patchedCode)) {
        patchedCode = patchedCode.replace(virtualizePatchPattern,
            `$1${STATIC_REGION_VIRTUALIZE_ADOPTION}
    $2`
        );
        console.log('[Codemod] Patched virtualize adoption point');
        patchCount++;
    } else {
        console.warn('[Codemod] Could not find virtualize adoption patch point');
    }

    // Patch 2: thunk-vs-thunk comparison for SPA navigation
    // Pattern: y.k = y.m(); return _VirtualDom_diffHelp(x.k, y.k, eventNode, tNode);
    // We want to insert our check BEFORE the y.m() call
    const spaNavigationPattern = /(var\s+xRefs\s*=\s*x\.l\s*;\s*var\s+yRefs\s*=\s*y\.l\s*;[\s\S]*?while\s*\(\s*same\s*&&\s*i\s*--\s*\)\s*\{[\s\S]*?\}\s*if\s*\(\s*same\s*\)\s*\{[\s\S]*?\})\s*(y\.k\s*=\s*y\.m\s*\(\s*\)\s*;)/;

    if (spaNavigationPattern.test(patchedCode)) {
        patchedCode = patchedCode.replace(spaNavigationPattern,
            `$1
                ${STATIC_REGION_SPA_NAVIGATION}
                $2`
        );
        console.log('[Codemod] Patched SPA navigation point');
        patchCount++;
    } else {
        console.warn('[Codemod] Could not find SPA navigation patch point');
    }

    console.log(`[Codemod] Applied ${patchCount} patches for elm-safe-virtual-dom`);
    return patchedCode;
}

export default { patchStaticRegionsESVD };
