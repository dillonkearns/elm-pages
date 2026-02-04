/**
 * Frozen View Codemod
 *
 * This codemod patches the compiled Elm virtual-dom code to support "frozen view adoption"
 * where pre-rendered HTML can be adopted by the virtual-dom without re-rendering.
 *
 * The patch intercepts the thunk (lazy) rendering to:
 * 1. Detect thunks with a magic string marker "__ELM_PAGES_STATIC__" in their refs
 * 2. On initial load: adopt existing DOM nodes with matching data-static attribute
 * 3. On SPA navigation: parse HTML strings from window.__ELM_PAGES_FROZEN_VIEWS__
 *
 * This enables dead-code elimination of frozen view dependencies (markdown parsers, etc.)
 * while preserving server-rendered HTML.
 *
 * Detection uses a magic string prefix instead of a custom type, which is more robust
 * because strings survive minification unchanged (unlike type tags which vary between
 * debug/optimized modes).
 */

import { patchFrozenViewsESVD } from "./frozen-view-codemod-esvd.js";

// Magic prefix for frozen view identification
const FROZEN_VIEW_PREFIX = '__ELM_PAGES_STATIC__';
const FROZEN_VIEW_PREFIX_LENGTH = FROZEN_VIEW_PREFIX.length; // 21

/**
 * Inlined frozen view handling code for the thunk render patch.
 * This gets inserted directly in the tag === 5 (THUNK) case.
 */
const FROZEN_VIEW_INLINE_CHECK = `
    // Frozen view adoption: check if this thunk is for a frozen view
    // Detection: refs[1] is a string starting with "__ELM_PAGES_STATIC__"
    var __frozenRefs = vNode.l;
    var __isFrozenView = __frozenRefs && __frozenRefs.length >= 2 &&
        typeof __frozenRefs[1] === 'string' &&
        __frozenRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');
    if (__isFrozenView) {
        var __frozenId = __frozenRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH});
        // Check global first (populated on SPA navigation BEFORE render)
        // This ensures we use the NEW page's content, not stale DOM from old page
        var __frozenViews = window.__ELM_PAGES_FROZEN_VIEWS__ || {};
        var __htmlFromGlobal = __frozenViews[__frozenId];
        if (__htmlFromGlobal && __htmlFromGlobal.length > 0) {
            var __template = document.createElement('template');
            __template.innerHTML = __htmlFromGlobal;
            var __newDom = __template.content.firstElementChild;
            if (__newDom) {
                vNode.k = _VirtualDom_virtualize(__newDom);
                return __newDom;
            }
        }
        // Fall back to DOM adoption (initial page load - global is empty {})
        var __existingDom = document.querySelector('[data-static="' + __frozenId + '"]');
        if (__existingDom) {
            if (__existingDom.parentNode) __existingDom.parentNode.removeChild(__existingDom);
            vNode.k = _VirtualDom_virtualize(__existingDom);
            return __existingDom;
        }
        var __placeholder = document.createElement('div');
        __placeholder.setAttribute('data-static', __frozenId);
        __placeholder.textContent = 'Loading frozen view...';
        return __placeholder;
    }
`;

/**
 * Inlined frozen view refs comparison for thunk diffing.
 *
 * For frozen views:
 * - On initial load: global is {}, so we compare by value and cache the adopted DOM
 * - On SPA navigation: global has content, so we virtualize from global instead of calling thunk
 *
 * This allows proper caching on initial load while ensuring navigation updates work.
 */
const FROZEN_VIEW_DIFF_CHECK = `
    // Frozen view: check if refs have magic string prefix
    var __xIsFrozen = xRefs && xRefs.length >= 2 && typeof xRefs[1] === 'string' && xRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');
    var __yIsFrozen = yRefs && yRefs.length >= 2 && typeof yRefs[1] === 'string' && yRefs[1].startsWith('${FROZEN_VIEW_PREFIX}');
    if (__xIsFrozen && __yIsFrozen) {
        var __frozenId = yRefs[1].slice(${FROZEN_VIEW_PREFIX_LENGTH});
        var __globalContent = (window.__ELM_PAGES_FROZEN_VIEWS__ || {})[__frozenId];
        if (__globalContent && __globalContent.length > 0) {
            // Global has content - SPA navigation
            // Use REDRAW with the thunk itself (y), not virtualized content
            // This way render will be called with the thunk, our interception fires,
            // and we parse HTML fresh with correct SVG namespace
            _VirtualDom_pushPatch(patches, 0, index, y);
            return;
        } else {
            // No global content - initial load, compare by value to enable caching
            // Strings compare by value, so this works correctly
            same = xRefs[1] === yRefs[1];
        }
    } else `;

/**
 * Auto-detecting frozen view patcher.
 *
 * Detects whether the compiled Elm code uses standard virtual-dom or elm-safe-virtual-dom
 * and applies the appropriate patches.
 *
 * Detection: elm-safe-virtual-dom uses a tNode parameter for DOM tracking, which appears
 * in patterns like `_VirtualDom_diffHelp(..., eventNode, tNode)`. Standard virtual-dom
 * does not have this parameter.
 *
 * @param {string} elmCode - The compiled Elm JavaScript code
 * @returns {string} - The patched code
 */
export function patchFrozenViews(elmCode) {
  // Detect elm-safe-virtual-dom by looking for the tNode parameter pattern
  const isESVD = /eventNode\s*,\s*tNode\s*\)/.test(elmCode);

  if (isESVD) {
    console.log("Detected elm-safe-virtual-dom, applying ESVD frozen view patches.");
    return patchFrozenViewsESVD(elmCode);
  }

  return patchFrozenViewsStandard(elmCode);
}

/**
 * Patches the thunk rendering code in the compiled Elm output for standard virtual-dom.
 *
 * Original thunk rendering (from kernel code):
 *   if (tag === __2_THUNK) {
 *     return _VirtualDom_render(vNode.__node || (vNode.__node = vNode.__thunk()), eventNode);
 *   }
 *
 * In compiled/optimized output this becomes something like:
 *   if (tag === 5) { return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode); }
 *
 * Patched version:
 *   if (tag === 5) {
 *     if (_VirtualDom_isFrozenView(vNode.l)) {
 *       return _VirtualDom_handleFrozenView(vNode, vNode.l, eventNode);
 *     }
 *     return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
 *   }
 *
 * Note: In compiled Elm output:
 * - Tag 5 = THUNK (lazy node)
 * - vNode.l = refs array (__refs)
 * - vNode.k = cached node (__node)
 * - vNode.m = thunk function (__thunk)
 */
export function patchFrozenViewsStandard(elmCode) {
  let patchedCode = elmCode;
  let patched = false;

  // Pattern 1: Standard debug/development mode
  // if (tag === 5) { return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode); }
  const debugPattern = /(if\s*\(\s*tag\s*===\s*5\s*\)\s*\{)\s*(return\s+_VirtualDom_render\s*\(\s*vNode\.k\s*\|\|\s*\(\s*vNode\.k\s*=\s*vNode\.m\s*\(\s*\)\s*\)\s*,\s*eventNode\s*\))/g;

  if (debugPattern.test(patchedCode)) {
    patchedCode = patchedCode.replace(debugPattern,
      `$1${FROZEN_VIEW_INLINE_CHECK}
    $2`
    );
    patched = true;
  }

  // Pattern 2: elm-hot injected pattern (might have slightly different formatting)
  if (!patched) {
    const elmHotPattern = /(if\s*\(\s*tag\s*===\s*5\s*\))\s*\{([^}]*return\s+_VirtualDom_render[^}]*)\}/g;

    if (elmHotPattern.test(patchedCode)) {
      patchedCode = patchedCode.replace(elmHotPattern, (match, condition, body) => {
        // Check if we already patched it
        if (body.includes('__frozenRefs')) {
          return match;
        }
        return `${condition} {${FROZEN_VIEW_INLINE_CHECK}
    ${body.trim()}
  }`;
      });
      patched = true;
    }
  }

  // Pattern 3: Very general fallback - just find the thunk case
  if (!patched) {
    // More lenient pattern: find "tag === 5" followed by return _VirtualDom_render
    const generalPattern = /(if\s*\(\s*tag\s*===\s*5\s*\)\s*\{[^}]*)(return\s+_VirtualDom_render)/;

    if (generalPattern.test(patchedCode)) {
      patchedCode = patchedCode.replace(generalPattern,
        `$1${FROZEN_VIEW_INLINE_CHECK}
    $2`
      );
      patched = true;
    }
  }

  if (!patched) {
    throw new Error('Could not patch thunk rendering for frozen views - virtual-dom structure may have changed');
  }

  // Now patch the thunk DIFFING code to handle frozen view comparison
  // The diff code compares refs by reference, but frozen views create new objects each render
  // We need to use value comparison for frozen views
  patchedCode = patchThunkDiffing(patchedCode);

  return patchedCode;
}

/**
 * Patches the thunk diffing code to handle frozen view comparison.
 *
 * Original diffing (in _VirtualDom_diffHelp, case 5 for THUNK):
 *   var xRefs = x.l;
 *   var yRefs = y.l;
 *   var i = xRefs.length;
 *   var same = i === yRefs.length;
 *   while (same && i--) {
 *       same = xRefs[i] === yRefs[i];
 *   }
 *   if (same) { y.k = x.k; return; }
 *
 * We need to add a special case for frozen views that detects the magic string prefix
 * and handles caching/navigation correctly.
 */
function patchThunkDiffing(elmCode) {
  // Look for the thunk diffing pattern in _VirtualDom_diffHelp
  // Pattern: case 5 followed by refs comparison loop

  // First, try to find and patch the specific pattern
  // The key is the "while (same && i--)" loop with "xRefs[i] === yRefs[i]"

  const diffPattern = /(case\s+5\s*:[\s\S]*?var\s+xRefs\s*=\s*x\.l\s*;[\s\S]*?var\s+yRefs\s*=\s*y\.l\s*;[\s\S]*?)(var\s+same\s*=\s*i\s*===\s*yRefs\.length\s*;[\s\S]*?while\s*\(\s*same\s*&&\s*i\s*--\s*\)\s*\{[\s\S]*?same\s*=\s*xRefs\[i\]\s*===\s*yRefs\[i\]\s*;[\s\S]*?\})/;

  if (diffPattern.test(elmCode)) {
    elmCode = elmCode.replace(diffPattern, (match, prefix, comparison) => {
      return `${prefix}${FROZEN_VIEW_DIFF_CHECK}{
				${comparison}
			}`;
    });
    return elmCode;
  }

  // Fallback: try a more lenient pattern
  // Look for the while loop with xRefs[i] === yRefs[i]
  const fallbackPattern = /(var\s+xRefs\s*=\s*x\.l[\s\S]{0,200}?)(while\s*\(\s*same\s*&&\s*i\s*--\s*\)\s*\{\s*same\s*=\s*xRefs\[i\]\s*===\s*yRefs\[i\]\s*;\s*\})/;

  if (fallbackPattern.test(elmCode)) {
    elmCode = elmCode.replace(fallbackPattern, (match, prefix, whileLoop) => {
      return `${prefix}${FROZEN_VIEW_DIFF_CHECK}{
				${whileLoop}
			}`;
    });
    return elmCode;
  }

  throw new Error('Could not patch thunk diffing for frozen views - virtual-dom structure may have changed');
}

export default { patchFrozenViews };
