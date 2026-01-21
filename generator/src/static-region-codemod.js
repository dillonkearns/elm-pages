/**
 * Static Region Codemod
 *
 * This codemod patches the compiled Elm virtual-dom code to support "static region adoption"
 * where pre-rendered HTML can be adopted by the virtual-dom without re-rendering.
 *
 * The patch intercepts the thunk (lazy) rendering to:
 * 1. Detect thunks with a StaticId marker in their refs
 * 2. On initial load: adopt existing DOM nodes with matching data-static attribute
 * 3. On SPA navigation: parse HTML strings into DOM nodes
 *
 * This enables dead-code elimination of static content dependencies (markdown parsers, etc.)
 * while preserving server-rendered HTML.
 */

/**
 * The code to inject that handles static region adoption.
 * This gets called inside the thunk rendering case.
 */
const STATIC_REGION_HANDLER = `
// Static region adoption handler
function _VirtualDom_handleStaticRegion(vNode, refs, eventNode) {
    // refs[0] is the function, refs[1] is StaticId, refs[2] is the HTML fallback string
    var staticId = refs[1];
    var htmlFallback = refs[2] || '';

    // Extract the ID string from the StaticId wrapper
    // StaticId is a custom type, so it's { $: 'StaticId', a: 'the-id-string' }
    var id = staticId.a;

    // Case 1: Initial page load - try to adopt existing DOM
    var existingDom = document.querySelector('[data-static="' + id + '"]');
    if (existingDom) {
        // Detach from old tree so it can be adopted into new tree
        if (existingDom.parentNode) {
            existingDom.parentNode.removeChild(existingDom);
        }
        // Store virtualized version for future diff comparisons
        // (though with stable refs, this should never actually be diffed)
        vNode.k = _VirtualDom_virtualize(existingDom);
        return existingDom;
    }

    // Case 2: SPA navigation - parse HTML string into DOM
    if (htmlFallback && htmlFallback.length > 0) {
        var template = document.createElement('template');
        template.innerHTML = htmlFallback;
        var newDom = template.content.firstElementChild;
        if (newDom) {
            vNode.k = _VirtualDom_virtualize(newDom);
            return newDom;
        }
    }

    // Case 3: Fallback - return empty text node (shouldn't happen in practice)
    console.warn('Static region "' + id + '" had no existing DOM and no HTML fallback');
    return document.createTextNode('');
}

// Check if a thunk's refs indicate it's a static region
function _VirtualDom_isStaticRegion(refs) {
    return refs && refs.length >= 2 && refs[1] && refs[1].$ === 'StaticId';
}

// Compare refs with special handling for StaticId (which creates new objects each render)
function _VirtualDom_staticRegionRefsEqual(xRefs, yRefs) {
    if (xRefs.length !== yRefs.length) return false;
    for (var i = 0; i < xRefs.length; i++) {
        var x = xRefs[i];
        var y = yRefs[i];
        // Special case for StaticId - compare by inner value, not reference
        if (x && y && x.$ === 'StaticId' && y.$ === 'StaticId') {
            if (x.a !== y.a) return false;
        } else if (x !== y) {
            return false;
        }
    }
    return true;
}
`;

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
  // First, inject our helper functions near the top of the file
  // We'll add them after the initial variable declarations
  const helperInjectionPoint = elmCode.indexOf('function _VirtualDom_');
  if (helperInjectionPoint === -1) {
    console.warn('Could not find VirtualDom functions to inject static region handler');
    return elmCode;
  }

  const codeWithHelpers =
    elmCode.slice(0, helperInjectionPoint) +
    STATIC_REGION_HANDLER + '\n' +
    elmCode.slice(helperInjectionPoint);

  // Now patch the thunk rendering case
  // We need to handle multiple possible patterns based on compilation mode

  let patchedCode = codeWithHelpers;
  let patched = false;

  // Pattern 1: Standard debug/development mode
  // if (tag === 5) { return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode); }
  const debugPattern = /(if\s*\(\s*tag\s*===\s*5\s*\)\s*\{)\s*(return\s+_VirtualDom_render\s*\(\s*vNode\.k\s*\|\|\s*\(\s*vNode\.k\s*=\s*vNode\.m\s*\(\s*\)\s*\)\s*,\s*eventNode\s*\))/g;

  if (debugPattern.test(patchedCode)) {
    patchedCode = patchedCode.replace(debugPattern,
      `$1
    if (_VirtualDom_isStaticRegion(vNode.l)) {
      return _VirtualDom_handleStaticRegion(vNode, vNode.l, eventNode);
    }
    $2`
    );
    patched = true;
    console.log('Patched using debug mode pattern');
  }

  // Pattern 2: elm-hot injected pattern (might have slightly different formatting)
  if (!patched) {
    const elmHotPattern = /(if\s*\(\s*tag\s*===\s*5\s*\))\s*\{([^}]*return\s+_VirtualDom_render[^}]*)\}/g;

    if (elmHotPattern.test(patchedCode)) {
      patchedCode = patchedCode.replace(elmHotPattern, (match, condition, body) => {
        // Check if we already patched it
        if (body.includes('_VirtualDom_isStaticRegion')) {
          return match;
        }
        return `${condition} {
    if (_VirtualDom_isStaticRegion(vNode.l)) {
      return _VirtualDom_handleStaticRegion(vNode, vNode.l, eventNode);
    }
    ${body.trim()}
  }`;
      });
      patched = true;
      console.log('Patched using elm-hot pattern');
    }
  }

  // Pattern 3: Very general fallback - just find the thunk case
  if (!patched) {
    console.log('Attempting general thunk patch...');

    // More lenient pattern: find "tag === 5" followed by return _VirtualDom_render
    const generalPattern = /(if\s*\(\s*tag\s*===\s*5\s*\)\s*\{[^}]*)(return\s+_VirtualDom_render)/;

    if (generalPattern.test(patchedCode)) {
      patchedCode = patchedCode.replace(generalPattern,
        `$1if (_VirtualDom_isStaticRegion(vNode.l)) { return _VirtualDom_handleStaticRegion(vNode, vNode.l, eventNode); }
    $2`
      );
      patched = true;
      console.log('Patched using general fallback pattern');
    }
  }

  if (!patched) {
    console.warn('Could not patch thunk rendering for static regions');
    console.warn('Looking for patterns in the code...');
    // Debug: show what patterns exist
    const thunkMatches = patchedCode.match(/tag\s*===\s*5/g);
    console.warn('Found "tag === 5" occurrences:', thunkMatches ? thunkMatches.length : 0);
  } else {
    console.log('Successfully patched virtual-dom for static region adoption');
  }

  // Now patch the thunk DIFFING code to handle StaticId comparison
  // The diff code compares refs by reference, but StaticId creates new objects each render
  // We need to use value comparison for StaticId
  patchedCode = patchThunkDiffing(patchedCode);

  return patchedCode;
}

/**
 * Patches the thunk diffing code to handle StaticId comparison.
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
 * We need to add a special case for static regions that compares StaticId by value.
 */
function patchThunkDiffing(elmCode) {
  // Look for the thunk diffing pattern in _VirtualDom_diffHelp
  // Pattern: case 5 followed by refs comparison loop

  // First, try to find and patch the specific pattern
  // The key is the "while (same && i--)" loop with "xRefs[i] === yRefs[i]"

  const diffPattern = /(case\s+5\s*:[\s\S]*?var\s+xRefs\s*=\s*x\.l\s*;[\s\S]*?var\s+yRefs\s*=\s*y\.l\s*;[\s\S]*?)(var\s+same\s*=\s*i\s*===\s*yRefs\.length\s*;[\s\S]*?while\s*\(\s*same\s*&&\s*i\s*--\s*\)\s*\{[\s\S]*?same\s*=\s*xRefs\[i\]\s*===\s*yRefs\[i\]\s*;[\s\S]*?\})/;

  if (diffPattern.test(elmCode)) {
    elmCode = elmCode.replace(diffPattern, (match, prefix, comparison) => {
      return `${prefix}// Static region: use value comparison for StaticId
			if (_VirtualDom_isStaticRegion(xRefs) && _VirtualDom_isStaticRegion(yRefs)) {
				var same = _VirtualDom_staticRegionRefsEqual(xRefs, yRefs);
			} else {
				${comparison}
			}`;
    });
    console.log('Successfully patched thunk diffing for static regions');
    return elmCode;
  }

  // Fallback: try a more lenient pattern
  // Look for the while loop with xRefs[i] === yRefs[i]
  const fallbackPattern = /(var\s+xRefs\s*=\s*x\.l[\s\S]{0,200}?)(while\s*\(\s*same\s*&&\s*i\s*--\s*\)\s*\{\s*same\s*=\s*xRefs\[i\]\s*===\s*yRefs\[i\]\s*;\s*\})/;

  if (fallbackPattern.test(elmCode)) {
    elmCode = elmCode.replace(fallbackPattern, (match, prefix, whileLoop) => {
      return `${prefix}if (_VirtualDom_isStaticRegion(xRefs) && _VirtualDom_isStaticRegion(yRefs)) {
				same = _VirtualDom_staticRegionRefsEqual(xRefs, yRefs);
			} else {
				${whileLoop}
			}`;
    });
    console.log('Successfully patched thunk diffing (fallback pattern)');
    return elmCode;
  }

  console.warn('Could not patch thunk diffing for static regions');
  return elmCode;
}

export default { patchStaticRegions };
