/**
 * Position-aware coverage flag extraction.
 *
 * Coverage flags before the script path are elm-pages options.
 * Coverage flags after the script path are forwarded to the script.
 *
 * We check process.argv for the original positions since Commander
 * consumes known options regardless of position.
 */

/**
 * @param {string} scriptPath - the resolved script path from Commander
 * @param {string[]} argv - process.argv
 * @returns {{ coverage: boolean, coverageInclude: string[], coverageExclude: string[], coverageIncludeModule: string[], coverageExcludeModule: string[] }}
 */
export function extractCoverageFlags(scriptPath, argv) {
  const result = {
    coverage: false,
    coverageInclude: [],
    coverageExclude: [],
    coverageIncludeModule: [],
    coverageExcludeModule: [],
  };

  // Find the script path in argv to determine the boundary
  const scriptIdx = argv.indexOf(scriptPath);
  if (scriptIdx === -1) return result;

  // Only consider args before the script path
  const preScript = argv.slice(0, scriptIdx);

  // Flags that take a value
  const keyMap = {
    "--coverage-include": "coverageInclude",
    "--coverage-exclude": "coverageExclude",
    "--coverage-include-module": "coverageIncludeModule",
    "--coverage-exclude-module": "coverageExcludeModule",
  };

  for (let i = 0; i < preScript.length; i++) {
    const arg = preScript[i];

    if (arg === "--coverage") {
      result.coverage = true;
    } else if (keyMap[arg] && i + 1 < preScript.length) {
      result[keyMap[arg]].push(preScript[i + 1]);
      i++; // skip value
    }
  }

  return result;
}
