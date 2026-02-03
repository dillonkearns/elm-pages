/**
 * Extract Frozen Views from Rendered HTML
 *
 * This module extracts all elements with `data-static` attributes from
 * rendered HTML and returns them as a map of {id: outerHTML}.
 *
 * This enables SPA navigation to use pre-rendered HTML for frozen views
 * without re-rendering on the client.
 */

/**
 * Extract all frozen views from HTML string.
 *
 * Handles three types of frozen view markers:
 * - Explicit IDs: data-static="my-id" → regions["my-id"]
 * - Route auto-indexed: data-static="__STATIC__" → regions["0"], regions["1"], etc.
 * - Shared auto-indexed: data-static="shared:__STATIC__" → regions["shared:0"], regions["shared:1"], etc.
 *
 * The __STATIC__ placeholder is replaced with sequential indices (0, 1, 2, ...)
 * in DOM order, matching the order that elm-review assigns to View.freeze calls.
 * Route and Shared frozen views have separate counters.
 *
 * @param {string} html - The rendered HTML containing data-static elements
 * @returns {Record<string, string>} Map of frozen view IDs to their outerHTML
 */
export function extractFrozenViews(html) {
  const regions = {};
  let sharedIndex = 0;
  let routeIndex = 0;

  // Find all data-static attributes and their values
  // Pattern: <tagname ... data-static="id" ...>
  const dataStaticPattern = /<(\w+)([^>]*)\sdata-static="([^"]+)"([^>]*)>/g;

  let match;
  while ((match = dataStaticPattern.exec(html)) !== null) {
    const tagName = match[1];
    let id = match[3];
    const startIndex = match.index;
    const placeholder = match[3];

    // Handle auto-indexed placeholders
    if (id === "shared:__STATIC__") {
      id = "shared:" + sharedIndex;
      sharedIndex++;
    } else if (id === "__STATIC__") {
      id = String(routeIndex);
      routeIndex++;
    }

    // Find the matching closing tag, handling nesting
    const outerHTML = extractElement(html, startIndex, tagName);

    if (outerHTML) {
      // If this was a placeholder, update the data-static attribute in the extracted HTML
      if (placeholder.includes("__STATIC__")) {
        regions[id] = outerHTML.replace(`data-static="${placeholder}"`, `data-static="${id}"`);
      } else {
        regions[id] = outerHTML;
      }
    }
  }

  return regions;
}

/**
 * Extract a complete element including nested tags.
 *
 * @param {string} html - The full HTML string
 * @param {number} startIndex - Index where the element starts
 * @param {string} tagName - The tag name to match
 * @returns {string|null} The complete element outerHTML, or null if not found
 */
function extractElement(html, startIndex, tagName) {
  let depth = 0;
  let i = startIndex;
  const openTag = new RegExp(`<${tagName}(?:\\s|>|/>)`, "i");
  const closeTag = new RegExp(`</${tagName}>`, "i");
  const selfClosing = new RegExp(`<${tagName}[^>]*/>`);

  // Check if it's a self-closing tag
  const selfCloseMatch = html.slice(startIndex).match(selfClosing);
  if (selfCloseMatch && selfCloseMatch.index === 0) {
    return selfCloseMatch[0];
  }

  // Find the first '>' to get past the opening tag
  while (i < html.length && html[i] !== ">") {
    i++;
  }
  i++; // Move past the '>'
  depth = 1;

  // Now scan for matching close tag
  while (i < html.length && depth > 0) {
    const remaining = html.slice(i);

    // Check for closing tag
    const closeMatch = remaining.match(closeTag);
    if (closeMatch && closeMatch.index === 0) {
      depth--;
      if (depth === 0) {
        const endIndex = i + closeMatch[0].length;
        return html.slice(startIndex, endIndex);
      }
      i += closeMatch[0].length;
      continue;
    }

    // Check for opening tag (same tag name, for nesting)
    const openMatch = remaining.match(openTag);
    if (openMatch && openMatch.index === 0) {
      // Check if it's self-closing
      const selfCloseCheck = remaining.match(selfClosing);
      if (selfCloseCheck && selfCloseCheck.index === 0) {
        i += selfCloseCheck[0].length;
        continue;
      }
      depth++;
      // Move past this opening tag
      let j = 0;
      while (j < remaining.length && remaining[j] !== ">") {
        j++;
      }
      i += j + 1;
      continue;
    }

    i++;
  }

  // If we didn't find the closing tag, return null
  return null;
}

/**
 * Replace all __STATIC__ placeholders in HTML with sequential indices.
 * Route and Shared frozen views have separate counters.
 *
 * @param {string} html - The HTML string containing __STATIC__ placeholders
 * @returns {string} The HTML with placeholders replaced by indices
 */
export function replaceFrozenViewPlaceholders(html) {
  let sharedIndex = 0;
  let routeIndex = 0;

  return html
    .replace(/data-static="shared:__STATIC__"/g, () => {
      return `data-static="shared:${sharedIndex++}"`;
    })
    .replace(/data-static="__STATIC__"/g, () => {
      return `data-static="${routeIndex++}"`;
    });
}

/**
 * Extract frozen views and return both the regions map and the updated HTML.
 *
 * @param {string} html - The rendered HTML containing data-static elements
 * @returns {{ regions: Record<string, string>, html: string }} Object with regions map and updated HTML
 */
export function extractAndReplaceFrozenViews(html) {
  const updatedHtml = replaceFrozenViewPlaceholders(html);
  const regions = extractFrozenViews(updatedHtml);
  return { regions, html: updatedHtml };
}

export default { extractFrozenViews, replaceFrozenViewPlaceholders, extractAndReplaceFrozenViews };
