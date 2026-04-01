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

/**
 * Commander consumes known options regardless of position. If coverage flags
 * appeared AFTER the script path in process.argv, they were intended for the
 * script but Commander ate them. Re-inject them into the unprocessed args.
 *
 * @param {string} scriptPath
 * @param {string[]} argv - process.argv
 * @param {object} commanderOptions - parsed options from Commander
 * @param {string[]} unprocessedCliOptions - mutable array to inject into
 */
export function reinjectConsumedFlags(scriptPath, argv, commanderOptions, unprocessedCliOptions) {
  const scriptIdx = argv.indexOf(scriptPath);
  if (scriptIdx === -1) return;

  const postScript = argv.slice(scriptIdx + 1);

  // Check each coverage flag: if it appears after the script in argv,
  // Commander consumed it but it was meant for the script.
  if (commanderOptions.coverage && postScript.includes("--coverage")) {
    unprocessedCliOptions.push("--coverage");
  }

  const withValue = {
    "--coverage-include": "coverageInclude",
    "--coverage-exclude": "coverageExclude",
    "--coverage-include-module": "coverageIncludeModule",
    "--coverage-exclude-module": "coverageExcludeModule",
  };

  for (const [flag, key] of Object.entries(withValue)) {
    const values = commanderOptions[key] || [];
    // For each value Commander captured, check if it came from after the script
    for (let i = 0; i < postScript.length; i++) {
      if (postScript[i] === flag && i + 1 < postScript.length) {
        unprocessedCliOptions.push(flag, postScript[i + 1]);
        i++;
      }
    }
  }
}
