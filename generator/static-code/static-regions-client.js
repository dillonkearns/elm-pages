/**
 * Client-side handling of static regions for SPA navigation.
 *
 * This module fetches static-regions.json files and populates
 * window.__ELM_PAGES_STATIC_REGIONS__ which is used by the virtual-dom codemod
 * to render static regions without re-executing the rendering code.
 */

/**
 * Fetch static regions for a given path and populate the global.
 *
 * @param {string} pathname - The path to fetch static regions for
 * @returns {Promise<Record<string, string>>} The static regions map
 */
export async function fetchStaticRegions(pathname) {
  // Ensure path ends with /
  let path = pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }

  try {
    const response = await fetch(`${window.location.origin}${path}static-regions.json`);

    if (response.ok) {
      const regions = await response.json();

      // Populate global for codemod to use
      window.__ELM_PAGES_STATIC_REGIONS__ = regions;

      return regions;
    } else if (response.status === 404) {
      // No static regions for this page - that's fine
      window.__ELM_PAGES_STATIC_REGIONS__ = {};
      return {};
    } else {
      console.warn(`Failed to fetch static regions: ${response.status}`);
      window.__ELM_PAGES_STATIC_REGIONS__ = {};
      return {};
    }
  } catch (error) {
    console.warn("Error fetching static regions:", error);
    window.__ELM_PAGES_STATIC_REGIONS__ = {};
    return {};
  }
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
 * Prefetch static regions for a given path (for link prefetching).
 *
 * @param {string} pathname - The path to prefetch static regions for
 */
export function prefetchStaticRegions(pathname) {
  let path = pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }

  const link = document.createElement("link");
  link.setAttribute("as", "fetch");
  link.setAttribute("rel", "prefetch");
  link.setAttribute("href", window.location.origin + path + "static-regions.json");
  document.head.appendChild(link);
}
