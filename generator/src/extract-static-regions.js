/**
 * Extract Static Regions from Rendered HTML
 *
 * This module extracts all elements with `data-static` attributes from
 * rendered HTML and returns them as a map of {id: outerHTML}.
 *
 * This enables SPA navigation to use pre-rendered HTML for static regions
 * without re-rendering on the client.
 */

/**
 * Extract all static regions from HTML string.
 *
 * @param {string} html - The rendered HTML containing data-static elements
 * @returns {Record<string, string>} Map of static region IDs to their outerHTML
 */
export function extractStaticRegions(html) {
  const regions = {};

  // Find all data-static attributes and their values
  // Pattern: <tagname ... data-static="id" ...>
  const dataStaticPattern = /<(\w+)([^>]*)\sdata-static="([^"]+)"([^>]*)>/g;

  let match;
  while ((match = dataStaticPattern.exec(html)) !== null) {
    const tagName = match[1];
    const id = match[3];
    const startIndex = match.index;

    // Find the matching closing tag, handling nesting
    const outerHTML = extractElement(html, startIndex, tagName);

    if (outerHTML) {
      regions[id] = outerHTML;
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

export default { extractStaticRegions };
