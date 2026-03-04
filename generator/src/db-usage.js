/**
 * Detect whether a script module uses Pages.Db directly or through local imports.
 */

import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Parse Elm import declarations from source text.
 * @param {string} source
 * @returns {string[]}
 */
function parseImports(source) {
  const imports = [];
  const importRegex = /^\s*import\s+([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\b/gm;
  let match;
  while ((match = importRegex.exec(source)) !== null) {
    imports.push(match[1]);
  }
  return imports;
}

/**
 * Load source directories from elm.json, falling back to the given source dir.
 * @param {string} projectDirectory
 * @param {string} fallbackSourceDirectory
 * @returns {string[]}
 */
function getSourceDirectories(projectDirectory, fallbackSourceDirectory) {
  const elmJsonPath = path.join(projectDirectory, "elm.json");
  if (!fs.existsSync(elmJsonPath)) {
    return [fallbackSourceDirectory];
  }

  try {
    const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
    const configured = (elmJson["source-directories"] || []).map((dir) =>
      path.resolve(projectDirectory, dir)
    );
    if (configured.length === 0) {
      return [fallbackSourceDirectory];
    }
    // Preserve order and remove duplicates
    return [...new Set(configured)];
  } catch (_) {
    return [fallbackSourceDirectory];
  }
}

/**
 * Resolve a module name to a local source file path.
 * @param {string} moduleName
 * @param {string[]} sourceDirectories
 * @returns {string | null}
 */
function resolveLocalModule(moduleName, sourceDirectories) {
  const relativePath = `${moduleName.split(".").join(path.sep)}.elm`;
  for (const sourceDir of sourceDirectories) {
    const candidate = path.join(sourceDir, relativePath);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

/**
 * Check whether the entry module imports Pages.Db directly or transitively
 * through local project modules.
 *
 * @param {{ projectDirectory: string, sourceDirectory: string, entryModuleName: string }} options
 * @returns {Promise<boolean>}
 */
export async function scriptUsesPagesDb({
  projectDirectory,
  sourceDirectory,
  entryModuleName,
}) {
  const sourceDirectories = getSourceDirectories(projectDirectory, sourceDirectory);
  const queue = [entryModuleName];
  const visited = new Set();

  while (queue.length > 0) {
    const moduleName = queue.pop();
    if (visited.has(moduleName)) {
      continue;
    }
    visited.add(moduleName);

    const modulePath = resolveLocalModule(moduleName, sourceDirectories);
    if (!modulePath) {
      continue;
    }

    const source = await fs.promises.readFile(modulePath, "utf8");
    const imports = parseImports(source);
    if (imports.includes("Pages.Db")) {
      return true;
    }

    for (const importedModule of imports) {
      if (!visited.has(importedModule)) {
        queue.push(importedModule);
      }
    }
  }

  return false;
}

