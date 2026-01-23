/**
 * Client-side handling of static regions for SPA navigation.
 *
 * This module fetches content.dat files which contain both static regions
 * and page data in a combined format:
 * [4 bytes: static regions JSON length (big-endian uint32)]
 * [N bytes: static regions JSON (UTF-8)]
 * [remaining bytes: ResponseSketch binary]
 *
 * The static regions are extracted and stored in window.__ELM_PAGES_STATIC_REGIONS__
 * which is used by the virtual-dom codemod to render static regions without
 * re-executing the rendering code.
 */

/**
 * Parse the combined content.dat format.
 *
 * @param {ArrayBuffer} buffer - The raw content.dat bytes
 * @returns {{ staticRegions: Record<string, string>, pageData: Uint8Array }}
 */
function parseCombinedContentDat(buffer) {
  const view = new DataView(buffer);

  // Read static regions JSON length (first 4 bytes, big-endian uint32)
  const staticRegionsLength = view.getUint32(0, false);

  // Extract static regions JSON
  const staticRegionsBytes = new Uint8Array(buffer, 4, staticRegionsLength);
  const staticRegionsJson = new TextDecoder().decode(staticRegionsBytes);
  const staticRegions = JSON.parse(staticRegionsJson);

  // Extract page data bytes (everything after the static regions)
  const pageData = new Uint8Array(buffer, 4 + staticRegionsLength);

  return { staticRegions, pageData };
}

/**
 * Fetch content.dat for a given path, parse the combined format,
 * set static regions global, and return both page data and raw bytes.
 *
 * @param {string} pathname - The path to fetch content for
 * @returns {Promise<{ staticRegions: Record<string, string>, pageData: Uint8Array, rawBytes: Uint8Array } | null>}
 */
export async function fetchContentWithStaticRegions(pathname) {
  // Ensure path ends with /
  let path = pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }

  try {
    const response = await fetch(`${window.location.origin}${path}content.dat`);

    if (response.ok) {
      const buffer = await response.arrayBuffer();
      const { staticRegions, pageData } = parseCombinedContentDat(buffer);

      // Populate global for codemod to use
      window.__ELM_PAGES_STATIC_REGIONS__ = staticRegions;

      // Return rawBytes (full content.dat) for Elm decoder which expects the prefix
      return { staticRegions, pageData, rawBytes: new Uint8Array(buffer) };
    } else if (response.status === 404) {
      // Page not found
      window.__ELM_PAGES_STATIC_REGIONS__ = {};
      return null;
    } else {
      console.warn(`Failed to fetch content.dat: ${response.status}`);
      window.__ELM_PAGES_STATIC_REGIONS__ = {};
      return null;
    }
  } catch (error) {
    console.warn("Error fetching content.dat:", error);
    window.__ELM_PAGES_STATIC_REGIONS__ = {};
    return null;
  }
}

/**
 * Fetch static regions for a given path and populate the global.
 * This is a convenience wrapper that discards the page data.
 *
 * @param {string} pathname - The path to fetch static regions for
 * @returns {Promise<Record<string, string>>} The static regions map
 */
export async function fetchStaticRegions(pathname) {
  const result = await fetchContentWithStaticRegions(pathname);
  return result?.staticRegions ?? {};
}

/**
 * Initialize static regions on initial page load.
 * This populates the global with an empty object - on initial load,
 * static regions are adopted from the existing DOM, not from the global.
 */
export function initStaticRegions() {
  // On initial load, static regions are adopted from existing DOM
  // The global is only used for SPA navigation
  window.__ELM_PAGES_STATIC_REGIONS__ = {};
}

/**
 * Prefetch content.dat for a given path (for link prefetching).
 * This prefetches the combined content.dat which includes both
 * static regions and page data.
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
export const prefetchStaticRegions = prefetchContentDat;
