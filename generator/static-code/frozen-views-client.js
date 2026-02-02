/**
 * Client-side handling of frozen views for SPA navigation.
 *
 * This module fetches content.dat files which contain both frozen views
 * and page data in a combined format:
 * [4 bytes: frozen views JSON length (big-endian uint32)]
 * [N bytes: frozen views JSON (UTF-8)]
 * [remaining bytes: ResponseSketch binary]
 *
 * The frozen views are extracted and stored in window.__ELM_PAGES_FROZEN_VIEWS__
 * which is used by the virtual-dom codemod to render frozen views without
 * re-executing the rendering code.
 */

/**
 * Parse the combined content.dat format.
 *
 * @param {ArrayBuffer} buffer - The raw content.dat bytes
 * @returns {{ frozenViews: Record<string, string>, pageData: Uint8Array }}
 */
function parseCombinedContentDat(buffer) {
  const view = new DataView(buffer);

  // Read frozen views JSON length (first 4 bytes, big-endian uint32)
  const frozenViewsLength = view.getUint32(0, false);

  // Extract frozen views JSON
  const frozenViewsBytes = new Uint8Array(buffer, 4, frozenViewsLength);
  const frozenViewsJson = new TextDecoder().decode(frozenViewsBytes);
  const frozenViews = JSON.parse(frozenViewsJson);

  // Extract page data bytes (everything after the frozen views)
  const pageData = new Uint8Array(buffer, 4 + frozenViewsLength);

  return { frozenViews, pageData };
}

/**
 * Fetch content.dat for a given path, parse the combined format,
 * set frozen views global, and return both page data and raw bytes.
 *
 * @param {string} pathname - The path to fetch content for
 * @param {string | null} query - Optional query string (without leading ?)
 * @returns {Promise<{ frozenViews: Record<string, string>, pageData: Uint8Array, rawBytes: Uint8Array } | null>}
 */
export async function fetchContentWithFrozenViews(pathname, query = null) {
  // Ensure path ends with /
  let path = pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }

  // Build the URL with optional query string
  let url = `${window.location.origin}${path}content.dat`;
  if (query) {
    url += `?${query}`;
  }

  try {
    const response = await fetch(url);

    if (response.ok) {
      const buffer = await response.arrayBuffer();
      const { frozenViews, pageData } = parseCombinedContentDat(buffer);

      // Populate global for codemod to use
      window.__ELM_PAGES_FROZEN_VIEWS__ = frozenViews;

      // Return rawBytes (full content.dat) for Elm decoder which expects the prefix
      return { frozenViews, pageData, rawBytes: new Uint8Array(buffer) };
    } else if (response.status === 404) {
      // Page not found
      window.__ELM_PAGES_FROZEN_VIEWS__ = {};
      return null;
    } else {
      console.warn(`Failed to fetch content.dat: ${response.status}`);
      window.__ELM_PAGES_FROZEN_VIEWS__ = {};
      return null;
    }
  } catch (error) {
    console.warn("Error fetching content.dat:", error);
    window.__ELM_PAGES_FROZEN_VIEWS__ = {};
    return null;
  }
}

/**
 * Fetch frozen views for a given path and populate the global.
 * This is a convenience wrapper that discards the page data.
 *
 * @param {string} pathname - The path to fetch frozen views for
 * @returns {Promise<Record<string, string>>} The frozen views map
 */
export async function fetchFrozenViews(pathname) {
  const result = await fetchContentWithFrozenViews(pathname);
  return result?.frozenViews ?? {};
}

/**
 * Initialize frozen views on initial page load.
 * Extracts frozen view HTML from the pre-rendered DOM BEFORE Elm initializes,
 * since Elm.Main.init() will replace the entire body content.
 *
 * The extracted HTML is stored in window.__ELM_PAGES_FROZEN_VIEWS__ where
 * the virtual-dom codemod will find it during rendering.
 */
export function initFrozenViews() {
  const frozenViews = {};

  // Find all elements with data-static attribute and extract their outerHTML
  // This must happen BEFORE Elm.Main.init() replaces the DOM
  document.querySelectorAll('[data-static]').forEach((element) => {
    const id = element.getAttribute('data-static');
    if (id !== null) {
      frozenViews[id] = element.outerHTML;
    }
  });

  window.__ELM_PAGES_FROZEN_VIEWS__ = frozenViews;
}

/**
 * Prefetch content.dat for a given path (for link prefetching).
 * This prefetches the combined content.dat which includes both
 * frozen views and page data.
 *
 * @param {string} pathname - The path to prefetch content for
 */
export function prefetchContentDat(pathname) {
  let path = pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }

  const link = document.createElement("link");
  link.setAttribute("as", "fetch");
  link.setAttribute("rel", "prefetch");
  link.setAttribute("href", window.location.origin + path + "content.dat");
  document.head.appendChild(link);
}

// Legacy alias for backwards compatibility
export const prefetchFrozenViews = prefetchContentDat;
