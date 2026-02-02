/**
 * Static Region Codemod
 *
 * This codemod patches the compiled Elm virtual-dom code to support "static region adoption"
 * where pre-rendered HTML can be adopted by the virtual-dom without re-rendering.
 *
 * The patch intercepts the thunk (lazy) rendering to:
 * 1. Detect thunks with a magic string marker "__ELM_PAGES_STATIC__" in their refs
 * 2. On initial load: adopt existing DOM nodes with matching data-static attribute
 * 3. On SPA navigation: parse HTML strings from window.__ELM_PAGES_STATIC_REGIONS__
 *
 * This enables dead-code elimination of static content dependencies (markdown parsers, etc.)
 * while preserving server-rendered HTML.
 *
 * Detection uses a magic string prefix instead of a custom type, which is more robust
 * because strings survive minification unchanged (unlike type tags which vary between
 * debug/optimized modes).
 */

// Magic prefix for static region identification
const STATIC_REGION_PREFIX = '__ELM_PAGES_STATIC__';
const STATIC_REGION_PREFIX_LENGTH = STATIC_REGION_PREFIX.length; // 21

/**
 * Inlined static region handling code for the thunk render patch.
 * This gets inserted directly in the tag === 5 (THUNK) case.
 */
const STATIC_REGION_INLINE_CHECK = `
    // Static region adoption: check if this thunk is for a static region
    // Detection: refs[1] is a string starting with "__ELM_PAGES_STATIC__"
    var __staticRefs = vNode.l;
    var __isStaticRegion = __staticRefs && __staticRefs.length >= 2 &&
        typeof __staticRefs[1] === 'string' &&
        __staticRefs[1].startsWith('${STATIC_REGION_PREFIX}');
    if (__isStaticRegion) {
        var __staticId = __staticRefs[1].slice(${STATIC_REGION_PREFIX_LENGTH});
        // Check global first (populated on SPA navigation BEFORE render)
        // This ensures we use the NEW page's content, not stale DOM from old page
        var __staticRegions = window.__ELM_PAGES_STATIC_REGIONS__ || {};
        var __htmlFromGlobal = __staticRegions[__staticId];
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
        var __existingDom = document.querySelector('[data-static="' + __staticId + '"]');
        if (__existingDom) {
            if (__existingDom.parentNode) __existingDom.parentNode.removeChild(__existingDom);
            vNode.k = _VirtualDom_virtualize(__existingDom);
            return __existingDom;
        }
        var __placeholder = document.createElement('div');
        __placeholder.setAttribute('data-static', __staticId);
        __placeholder.textContent = 'Loading static region...';
        return __placeholder;
    }
`;

/**
 * Inlined static region refs comparison for thunk diffing.
 *
 * For static regions:
 * - On initial load: global is {}, so we compare by value and cache the adopted DOM
 * - On SPA navigation: global has content, so we virtualize from global instead of calling thunk
 *
 * This allows proper caching on initial load while ensuring navigation updates work.
 */
const STATIC_REGION_DIFF_CHECK = `
    // Static region: check if refs have magic string prefix
    var __xIsStatic = xRefs && xRefs.length >= 2 && typeof xRefs[1] === 'string' && xRefs[1].startsWith('${STATIC_REGION_PREFIX}');
    var __yIsStatic = yRefs && yRefs.length >= 2 && typeof yRefs[1] === 'string' && yRefs[1].startsWith('${STATIC_REGION_PREFIX}');
    if (__xIsStatic && __yIsStatic) {
        var __staticId = yRefs[1].slice(${STATIC_REGION_PREFIX_LENGTH});
        var __globalContent = (window.__ELM_PAGES_STATIC_REGIONS__ || {})[__staticId];
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
 * Patches the thunk rendering code in the compiled Elm output.
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
 *     if (_VirtualDom_isStaticRegion(vNode.l)) {
 *       return _VirtualDom_handleStaticRegion(vNode, vNode.l, eventNode);
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
export function patchStaticRegions(elmCode) {
  let patchedCode = elmCode;
  let patched = false;

  // Pattern 1: Standard debug/development mode
  // if (tag === 5) { return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode); }
  const debugPattern = /(if\s*\(\s*tag\s*===\s*5\s*\)\s*\{)\s*(return\s+_VirtualDom_render\s*\(\s*vNode\.k\s*\|\|\s*\(\s*vNode\.k\s*=\s*vNode\.m\s*\(\s*\)\s*\)\s*,\s*eventNode\s*\))/g;

  if (debugPattern.test(patchedCode)) {
    patchedCode = patchedCode.replace(debugPattern,
      `$1${STATIC_REGION_INLINE_CHECK}
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
        if (body.includes('__staticRefs')) {
          return match;
        }
        return `${condition} {${STATIC_REGION_INLINE_CHECK}
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
        `$1${STATIC_REGION_INLINE_CHECK}
    $2`
      );
      patched = true;
    }
  }

  if (!patched) {
    throw new Error('Could not patch thunk rendering for static regions - virtual-dom structure may have changed');
  }

  // Now patch the thunk DIFFING code to handle StaticId comparison
  // The diff code compares refs by reference, but StaticId creates new objects each render
  // We need to use value comparison for StaticId
  patchedCode = patchThunkDiffing(patchedCode);

  return patchedCode;
}

/**
 * Patches the thunk diffing code to handle static region comparison.
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
 * We need to add a special case for static regions that detects the magic string prefix
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
      return `${prefix}${STATIC_REGION_DIFF_CHECK}{
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
      return `${prefix}${STATIC_REGION_DIFF_CHECK}{
				${whileLoop}
			}`;
    });
    return elmCode;
  }

  throw new Error('Could not patch thunk diffing for static regions - virtual-dom structure may have changed');
}

export default { patchStaticRegions };
