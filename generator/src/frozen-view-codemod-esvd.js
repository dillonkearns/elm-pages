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
                // x is the virtual node for that DOM, so later diffs have
                // something real to compare against.
                y.k = x;
                __existingDom.elmPagesFrozenHtml = (window.__ELM_PAGES_FROZEN_VIEWS__ || {})[__frozenId];
                return {
                    r: __existingDom,
                    u: false,
                    v: false
                };
            }
        }

        // Something else is on the page here (SPA navigation to a page with a
        // frozen view in this spot). Replace it with the frozen view, drawn from
        // its saved HTML (see the patch in _VirtualDom_render).
        if (((window.__ELM_PAGES_FROZEN_VIEWS__ || {})[__frozenId] || '').length > 0) {
            return _VirtualDom_applyPatchRedraw(x, y, eventNode, tNode);
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
    // Detection: refs[1] is a string starting with "${FROZEN_VIEW_PREFIX}"
    var __yIsFrozen = yRefs && yRefs.length >= 2 && typeof yRefs[1] === 'string' && yRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');
    var __xIsFrozen = xRefs && xRefs.length >= 2 && typeof xRefs[1] === 'string' && xRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');

    if (__yIsFrozen && __xIsFrozen) {
        var __newFrozenId = yRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH});
        var __oldFrozenId = xRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH});
        var __globalContent = (window.__ELM_PAGES_FROZEN_VIEWS__ || {})[__newFrozenId];
        var __existingDom = tNode.r;

        // Case 1: the frozen view on the page is already this one (a re-render
        // of the same page). Keep the DOM, skip thunk evaluation.
        // Two pages can both have a frozen view "0", so the id alone is not
        // enough: the DOM must also have been made from the current HTML.
        if (__newFrozenId === __oldFrozenId && __existingDom && __existingDom.nodeType === 1 &&
            (!__globalContent || __existingDom.elmPagesFrozenHtml === __globalContent)) {
            y.k = x.k;
            return {
                r: __existingDom,
                u: false,
                v: false
            };
        }

        // Case 2: a different frozen view (SPA navigation). Draw it from its
        // saved HTML (see the patch in _VirtualDom_render) in place of the old one.
        if (__globalContent && __globalContent.length > 0 && x.k) {
            return _VirtualDom_applyPatchRedraw(x.k, y, eventNode, tNode);
        }
    }
`;

/**
 * Patch for rendering a frozen view from scratch, in _VirtualDom_render.
 *
 * The app's first render happens before the page data has arrived, and replaces
 * the server-rendered page. So when the real view is drawn, its frozen views are
 * new nodes that go through render, not through the diff. The same happens
 * whenever a frozen view appears where there was none before.
 *
 * Original:
 *   if (tag === 5) {
 *       return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode, tNode);
 *   }
 *
 * The frozen view's HTML is in window.__ELM_PAGES_FROZEN_VIEWS__ (saved from the
 * server-rendered page before the app starts, and replaced on SPA navigation).
 * We build the DOM from it, and virtualize it so that the thunk has a real
 * virtual node (and tNode a real tree) for later diffs.
 */
const FROZEN_VIEW_RENDER = `
        // Frozen view: draw it from its saved HTML instead of evaluating the thunk
        // Detection: refs[1] is a string starting with "${FROZEN_VIEW_PREFIX}"
        var __frozenRefs = vNode.l;
        if (__frozenRefs && __frozenRefs.length >= 2 &&
            typeof __frozenRefs[1] === 'string' &&
            __frozenRefs[1].startsWith('${FROZEN_VIEW_PREFIX}')) {
            var __frozenHtml = (window.__ELM_PAGES_FROZEN_VIEWS__ || {})[__frozenRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH})];
            if (__frozenHtml && __frozenHtml.length > 0) {
                var __template = document.createElement('template');
                __template.innerHTML = __frozenHtml;
                var __frozenDom = __template.content.firstElementChild;
                if (__frozenDom) {
                    tNode.r = __frozenDom;
                    tNode.s = Object.create(null);
                    vNode.k = _VirtualDom_virtualizeHelp(__frozenDom, tNode);
                    __frozenDom.elmPagesFrozenHtml = __frozenHtml;
                    return __frozenDom;
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

    // Patch 3: rendering a frozen view from scratch
    // Pattern: if (tag === 5) { return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode, tNode); }
    const renderPattern = /(if\s*\(\s*tag\s*===\s*5\s*\)\s*\{)\s*(return\s+_VirtualDom_render\s*\(\s*vNode\.k\s*\|\|\s*\(\s*vNode\.k\s*=\s*vNode\.m\s*\(\s*\)\s*\)\s*,\s*eventNode\s*,\s*tNode\s*\))/;

    if (renderPattern.test(patchedCode)) {
        patchedCode = patchedCode.replace(renderPattern,
            `$1${FROZEN_VIEW_RENDER}
        $2`
        );
        patchCount++;
    }

    if (patchCount < 3) {
        throw new Error(`[frozen-view-codemod-esvd] Only applied ${patchCount}/3 patches - elm-safe-virtual-dom structure may have changed`);
    }

    return patchedCode;
}

export default { patchFrozenViewsESVD };
