import * as fs from "node:fs";
import * as fsExtra from "fs-extra";
import { rewriteElmJson } from "./rewrite-elm-json.js";
import { rewriteClientElmJson } from "./rewrite-client-elm-json.js";
import { elmPagesCliFile, elmPagesUiFile } from "./elm-file-constants.js";
import { spawn as spawnCallback } from "cross-spawn";
import { default as which } from "which";
import { generateTemplateModuleConnector } from "./generate-template-module-connector.js";

import * as path from "path";
import { ensureDirSync, deleteIfExists, writeFileIfChanged, copyDirIfNewer, copyFileIfNewer } from "./file-helpers.js";
import { fileURLToPath } from "url";
global.builtAt = new Date();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * @param {string} basePath
 */
export async function generate(basePath) {
  // In dev mode, skip ephemeral field analysis since the server-review codemod
  // that creates Ephemeral types in route modules isn't run.
  // Ephemeral type optimization only matters for production builds.
  const cliCode = await generateTemplateModuleConnector(basePath, "cli", {
    skipEphemeralAnalysis: true,
  });
  const browserCode = await generateTemplateModuleConnector(
    basePath,
    "browser"
  );
  ensureDirSync("./elm-stuff");
  ensureDirSync("./.elm-pages");
  ensureDirSync("./gen");
  ensureDirSync("./elm-stuff/elm-pages/.elm-pages");

  const uiFileContent = elmPagesUiFile();

  await Promise.all([
    copyToBoth("RouteBuilder.elm"),
    copyToBoth("SharedTemplate.elm"),
    copyToBoth("SiteConfig.elm"),

    writeFileIfChanged("./.elm-pages/Pages.elm", uiFileContent),
    copyFileIfNewer(
      path.join(__dirname, `./elm-application.json`),
      `./elm-stuff/elm-pages/elm-application.json`
    ),
    // write `Pages.elm` with cli interface
    writeFileIfChanged(
      "./elm-stuff/elm-pages/.elm-pages/Pages.elm",
      elmPagesCliFile()
    ),
    writeFileIfChanged(
      "./elm-stuff/elm-pages/.elm-pages/Main.elm",
      cliCode.mainModule
    ),
    writeFileIfChanged(
      "./elm-stuff/elm-pages/.elm-pages/Route.elm",
      cliCode.routesModule
    ),
    writeFileIfChanged("./.elm-pages/Main.elm", browserCode.mainModule),
    writeFileIfChanged("./.elm-pages/Route.elm", browserCode.routesModule),
    writeFetcherModules("./.elm-pages", browserCode.fetcherModules),
    writeFetcherModules(
      "./elm-stuff/elm-pages/client/.elm-pages",
      browserCode.fetcherModules
    ),
    writeFetcherModules(
      "./elm-stuff/elm-pages/.elm-pages",
      browserCode.fetcherModules
    ),
    // write modified elm.json to elm-stuff/elm-pages/
    rewriteElmJson("./elm.json", "./elm-stuff/elm-pages/elm.json"),
    // ...(await listFiles("./Pages/Internal")).map(copyToBoth),
  ]);
}

function writeFetcherModules(basePath, fetcherData) {
  return Promise.all(
    fetcherData.map(([name, fileContent]) => {
      let filePath = path.join(basePath, `/Fetcher/${name.join("/")}.elm`);
      ensureDirSync(path.dirname(filePath));
      return writeFileIfChanged(filePath, fileContent);
    })
  );
}

async function newCopyBoth(modulePath) {
  await copyFileIfNewer(
    path.join(__dirname, modulePath),
    path.join(`./elm-stuff/elm-pages/client/.elm-pages/`, modulePath)
  );
}

/**
 * Generate the client folder with client-specific codemods.
 * @param {string} basePath
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>, deOptimizationCount: number, unsupportedHelperSeedingIssues: Array<{path: string, message: string}>}>}
 */
export async function generateClientFolder(basePath) {
  const browserCode = await generateTemplateModuleConnector(
    basePath,
    "browser"
  );
  const uiFileContent = elmPagesUiFile();
  ensureDirSync("./elm-stuff/elm-pages/client/app");
  ensureDirSync("./elm-stuff/elm-pages/client/.elm-pages");
  await newCopyBoth("RouteBuilder.elm");
  await newCopyBoth("SharedTemplate.elm");
  await newCopyBoth("SiteConfig.elm");

  await rewriteClientElmJson();
  await copyDirIfNewer("./app", "./elm-stuff/elm-pages/client/app");

  await writeFileIfChanged(
    "./elm-stuff/elm-pages/client/.elm-pages/Main.elm",
    browserCode.mainModule
  );
  await writeFileIfChanged(
    "./elm-stuff/elm-pages/client/.elm-pages/Route.elm",
    browserCode.routesModule
  );
  await writeFileIfChanged(
    "./elm-stuff/elm-pages/client/.elm-pages/Pages.elm",
    uiFileContent
  );
  const result = await runElmReviewCodemod("./elm-stuff/elm-pages/client/");
  return {
    ephemeralFields: result.ephemeralFields,
    deOptimizationCount: result.deOptimizationCount || 0,
    unsupportedHelperSeedingIssues:
      result.unsupportedHelperSeedingIssues || [],
  };
}

/**
 * Generate the server folder with server-specific codemods.
 * @param {string} basePath
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>, unsupportedHelperSeedingIssues: Array<{path: string, message: string}>}>}
 */
export async function generateServerFolder(basePath) {
  ensureDirSync("./elm-stuff/elm-pages/server/app");
  ensureDirSync("./elm-stuff/elm-pages/server/.elm-pages");

  // Copy RouteBuilder and other framework files to server folder
  await Promise.all([
    copyFileEnsureDir(
      path.join(__dirname, "RouteBuilder.elm"),
      "./elm-stuff/elm-pages/server/.elm-pages/RouteBuilder.elm"
    ),
    copyFileEnsureDir(
      path.join(__dirname, "SharedTemplate.elm"),
      "./elm-stuff/elm-pages/server/.elm-pages/SharedTemplate.elm"
    ),
    copyFileEnsureDir(
      path.join(__dirname, "SiteConfig.elm"),
      "./elm-stuff/elm-pages/server/.elm-pages/SiteConfig.elm"
    ),
  ]);

  // Rewrite elm.json for server folder (3 levels deep, so need ../../../)
  // Keep app/ local since we copy the app files to server folder for transformation
  await rewriteElmJson("./elm.json", "./elm-stuff/elm-pages/server/elm.json", {
    pathPrefix: "../../../",
    keepAppLocal: true,
  });

  // Copy app files to server folder
  await copyDirIfNewer("./app", "./elm-stuff/elm-pages/server/app");

  // Run server-specific elm-review codemod FIRST
  // This creates the Ephemeral type alias in Route files
  // Must run before generateTemplateModuleConnector so Main.elm can reference Ephemeral
  const serverResult = await runElmReviewCodemod("./elm-stuff/elm-pages/server/", "server");

  // Now generate Main.elm which can reference Route.Index.Ephemeral etc.
  const cliCode = await generateTemplateModuleConnector(basePath, "cli");

  // Generate browser code to get Fetcher modules (needed for route modules that import Fetchers)
  const browserCode = await generateTemplateModuleConnector(basePath, "browser");

  // Write generated Main.elm, Route.elm, Pages.elm
  await writeFileIfChanged(
    "./elm-stuff/elm-pages/server/.elm-pages/Main.elm",
    cliCode.mainModule
  );
  await writeFileIfChanged(
    "./elm-stuff/elm-pages/server/.elm-pages/Route.elm",
    cliCode.routesModule
  );
  await writeFileIfChanged(
    "./elm-stuff/elm-pages/server/.elm-pages/Pages.elm",
    elmPagesCliFile()
  );

  // Write Fetcher modules to server folder (needed for route modules that import Fetchers)
  await writeFetcherModules(
    "./elm-stuff/elm-pages/server/.elm-pages",
    browserCode.fetcherModules
  );

  return {
    ephemeralFields: serverResult.ephemeralFields,
    unsupportedHelperSeedingIssues:
      serverResult.unsupportedHelperSeedingIssues || [],
  };
}

/**
 * @param {string} [ cwd ]
 * @param {"client" | "server"} [ target ] - which codemod config to use (default: client)
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>, deOptimizationCount: number, unsupportedHelperSeedingIssues: Array<{path: string, message: string}>, codemodFixesApplied: boolean}>}
 */
export async function runElmReviewCodemod(cwd, target = "client") {
  // Use different elm-review configs for client vs server transformations
  const configPath =
    target === "server"
      ? path.join(__dirname, "../../generator/server-review")
      : path.join(__dirname, "../../generator/dead-code-review");

  const cwdPath = path.join(process.cwd(), cwd || ".");
  const lamderaPath = await which("lamdera");

  // Run elm-review without fixes first to capture EPHEMERAL_FIELDS_JSON for analysis
  const analysisOutput = await runElmReviewCommand(cwdPath, configPath, lamderaPath, false);
  const ephemeralFields = parseEphemeralFieldsWithFields(analysisOutput);
  const deOptimizationCount = parseDeOptimizationCount(analysisOutput);
  const unsupportedHelperSeedingIssues = parseUnsupportedHelperSeedingIssues(
    analysisOutput,
    target
  );

  // If helper ID seeding is unsupported in this target, skip codemod fixes and
  // fall back to untransformed source (safe de-optimization).
  if (unsupportedHelperSeedingIssues.length === 0) {
    // Now run elm-review with fixes
    await runElmReviewCommand(cwdPath, configPath, lamderaPath, true);
  }

  return {
    ephemeralFields,
    deOptimizationCount,
    unsupportedHelperSeedingIssues,
    codemodFixesApplied: unsupportedHelperSeedingIssues.length === 0,
  };
}

/**
 * Parse DEOPTIMIZATION_COUNT_JSON messages from elm-review output.
 * Returns the total count of de-optimized View.freeze calls.
 * @param {string} elmReviewOutput
 * @returns {number}
 */
export function parseDeOptimizationCount(elmReviewOutput) {
  let count = 0;
  let jsonOutput;
  try {
    jsonOutput = JSON.parse(elmReviewOutput);
  } catch (e) {
    return count;
  }

  if (!jsonOutput.errors) {
    return count;
  }

  for (const fileErrors of jsonOutput.errors) {
    for (const error of fileErrors.errors) {
      if (error.message && error.message.startsWith("DEOPTIMIZATION_COUNT_JSON:")) {
        try {
          const jsonStr = error.message.slice("DEOPTIMIZATION_COUNT_JSON:".length);
          const data = JSON.parse(jsonStr);
          if (data.count) {
            count += data.count;
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }
  }

  return count;
}

/**
 * Parse unsupported helper ID seeding diagnostics from elm-review output.
 * These indicate patterns where helper ID auto-seeding is not currently supported
 * (for example function-value/partial usage or repeated contexts like List.map).
 *
 * @param {string} elmReviewOutput
 * @param {"client" | "server"} [target]
 * @returns {Array<{path: string, message: string}>}
 */
export function parseUnsupportedHelperSeedingIssues(
  elmReviewOutput,
  target = "client"
) {
  let jsonOutput;
  try {
    jsonOutput = JSON.parse(elmReviewOutput);
  } catch (e) {
    return [];
  }

  if (!jsonOutput.errors) {
    return [];
  }

  const messagePrefix =
    target === "server"
      ? "Server codemod: unsupported helper"
      : "Frozen view codemod: unsupported helper";

  const issues = [];

  for (const fileErrors of jsonOutput.errors) {
    for (const error of fileErrors.errors) {
      if (
        error.message &&
        typeof error.message === "string" &&
        error.message.startsWith(messagePrefix)
      ) {
        issues.push({
          path: fileErrors.path,
          message: error.message,
        });
      }
    }
  }

  return issues;
}

/**
 * Run elm-review command
 * @param {string} cwdPath
 * @param {string} configPath
 * @param {string} lamderaPath
 * @param {boolean} applyFixes
 */
async function runElmReviewCommand(cwdPath, configPath, lamderaPath, applyFixes) {
  const args = [
    "--report", "json",
    "--namespace", "elm-pages",
    "--config", configPath,
    "--elmjson", "elm.json",
    "--compiler", lamderaPath,
  ];
  if (applyFixes) {
    args.unshift("--fix-all-without-prompt");
  }

  return new Promise((resolve, reject) => {
    const child = spawnCallback("elm-review", args, { cwd: cwdPath });

    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", function (/** @type {string} */ data) {
      stdout += data.toString();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", function (/** @type {string} */ data) {
      stderr += data.toString();
    });
    child.on("error", function () {
      reject(stdout + stderr);
    });

    child.on("close", function (code) {
      // Check for elm-review crashes (stack overflow, missing elm.json, config errors, etc.)
      // These have {"type":"error",...} in the JSON output, as opposed to
      // {"type":"review-errors",...} for normal review results.
      const combined = stdout + stderr;
      const output = stdout || combined;
      const crashError = extractElmReviewCrashError(output);
      if (crashError) {
        reject(new Error(`elm-review crashed: ${crashError.title}\n${crashError.message}`));
        return;
      }

      let parsedOutput = null;
      try {
        parsedOutput = JSON.parse(output);
      } catch (e) {
        // non-JSON output handled by string checks below
      }

      if (parsedOutput && parsedOutput.type === "compile-errors") {
        reject(combined);
        return;
      }

      if (code === 0 || !applyFixes) {
        // For analysis-only run, exit code 1 is expected (review errors found)
        resolve(output);
      } else {
        // When applying fixes, elm-review returns non-zero when fixes are
        // already applied ("failing fix"), which is expected.
        // Reject only on real parse/compile/config failures.
        const hasRealError = combined.includes("PARSING ERROR") ||
          combined.includes("COMPILE ERROR") ||
          combined.includes("CONFIGURATION ERROR") ||
          combined.includes("\"type\":\"compile-errors\"") ||
          combined.includes("\"type\":\"error\"");
        if (hasRealError) {
          reject(combined);
        } else {
          resolve(output);
        }
      }
    });
  });
}

/**
 * Check if elm-review output indicates a crash (as opposed to normal review errors).
 *
 * Normal review output has {"type":"review-errors",...} at the top level.
 * Crash output has {"type":"error","title":"...","message":[...]} at the top level.
 *
 * This catches all crash types: UNEXPECTED ERROR (stack overflow), ELM.JSON NOT FOUND,
 * CONFIGURATION ERROR, PARSING ERROR, COMPILE ERROR, etc.
 *
 * @param {string} output - raw elm-review output (may contain multiple JSON objects)
 * @returns {{title: string, message: string} | null} - crash info, or null if no crash
 */
export function extractElmReviewCrashError(output) {
  try {
    const parsed = JSON.parse(output);
    if (parsed && parsed.type === "error") {
      const title = parsed.title || "Unknown error";
      const message = Array.isArray(parsed.message)
        ? parsed.message.join("")
        : (parsed.message || "");
      return { title, message };
    }
  } catch (e) {
    // Output isn't valid JSON - could be a raw error message from a missing binary etc.
    // Check for common non-JSON crash indicators
    if (output.includes("command not found") || output.includes("ENOENT")) {
      return { title: "elm-review not found", message: output };
    }
  }
  return null;
}

/**
 * Parse EPHEMERAL_FIELDS_JSON messages from elm-review output
 * @param {string} elmReviewOutput
 * @returns {Array<{filePath: string, module: string, newDataType: string, range: object}>}
 */
function parseEphemeralFieldsJson(elmReviewOutput) {
  let jsonOutput;
  try {
    jsonOutput = JSON.parse(elmReviewOutput);
  } catch (e) {
    return [];
  }

  if (!jsonOutput.errors) {
    return [];
  }

  const fixes = [];
  for (const fileErrors of jsonOutput.errors) {
    const filePath = fileErrors.path;
    for (const error of fileErrors.errors) {
      if (error.message && error.message.startsWith("EPHEMERAL_FIELDS_JSON:")) {
        try {
          const jsonStr = error.message.slice("EPHEMERAL_FIELDS_JSON:".length);
          const data = JSON.parse(jsonStr);
          if (data.newDataType && data.range) {
            fixes.push({
              filePath,
              module: data.module,
              newDataType: data.newDataType,
              range: data.range,
            });
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }
  }

  return fixes;
}

/**
 * Parse EPHEMERAL_FIELDS_JSON messages and extract module → Set of ephemeral field names.
 * This is used for comparing server and client ephemeral field analysis.
 * @param {string} elmReviewOutput
 * @returns {Map<string, Set<string>>} Map from module name to set of ephemeral field names
 */
function parseEphemeralFieldsWithFields(elmReviewOutput) {
  /** @type {Map<string, Set<string>>} */
  const result = new Map();

  let jsonOutput;
  try {
    jsonOutput = JSON.parse(elmReviewOutput);
  } catch (e) {
    return result;
  }

  if (!jsonOutput.errors) {
    return result;
  }

  for (const fileErrors of jsonOutput.errors) {
    for (const error of fileErrors.errors) {
      if (error.message && error.message.startsWith("EPHEMERAL_FIELDS_JSON:")) {
        try {
          const jsonStr = error.message.slice("EPHEMERAL_FIELDS_JSON:".length);
          const data = JSON.parse(jsonStr);
          if (data.module && data.ephemeralFields && Array.isArray(data.ephemeralFields)) {
            const existingFields = result.get(data.module) || new Set();
            for (const field of data.ephemeralFields) {
              existingFields.add(field);
            }
            result.set(data.module, existingFields);
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }
  }

  return result;
}

/**
 * Compare ephemeral fields from server and client transforms.
 * Returns null if they agree, or a list of disagreements if they differ.
 * @param {Map<string, Set<string>>} serverFields
 * @param {Map<string, Set<string>>} clientFields
 * @returns {{disagreements: Array<{module: string, serverOnly: string[], clientOnly: string[]}>} | null}
 */
export function compareEphemeralFields(serverFields, clientFields) {
  const disagreements = [];
  const allModules = new Set([...serverFields.keys(), ...clientFields.keys()]);

  for (const module of allModules) {
    const serverSet = serverFields.get(module) || new Set();
    const clientSet = clientFields.get(module) || new Set();

    const serverOnly = [...serverSet].filter(f => !clientSet.has(f));
    const clientOnly = [...clientSet].filter(f => !serverSet.has(f));

    if (serverOnly.length > 0 || clientOnly.length > 0) {
      disagreements.push({ module, serverOnly, clientOnly });
    }
  }

  return disagreements.length > 0 ? { disagreements } : null;
}

/**
 * Format a disagreement error for display.
 * @param {{disagreements: Array<{module: string, serverOnly: string[], clientOnly: string[]}>}} comparison
 * @returns {string}
 */
export function formatDisagreementError(comparison) {
  const lines = [
    "\n=== EPHEMERAL FIELD DISAGREEMENT ===\n",
    "Server and client transforms disagree on which Data fields are ephemeral.",
    "This is likely a bug. Please report at https://github.com/dillonkearns/elm-pages/issues\n"
  ];

  for (const { module, serverOnly, clientOnly } of comparison.disagreements) {
    lines.push(`Module: ${module}`);
    for (const field of serverOnly) {
      lines.push(`  Field "${field}": server says ephemeral, client says persistent`);
    }
    for (const field of clientOnly) {
      lines.push(`  Field "${field}": client says ephemeral, server says persistent`);
    }
  }

  return lines.join("\n");
}

/**
 * Apply Data type fixes that elm-review may have failed to apply correctly.
 * This is a workaround for elm-review's fix application bug with multi-line ranges.
 *
 * @param {string} cwd - working directory
 * @param {Array<{filePath: string, module: string, newDataType: string, range: object}>} fixes
 */
async function applyDataTypeFixes(cwd, fixes) {
  // Apply fixes to each file
  for (const fix of fixes) {
    const fullPath = path.join(process.cwd(), cwd || ".", fix.filePath);
    try {
      const content = await fs.promises.readFile(fullPath, "utf8");

      // Find "type alias Data =" and replace the record definition after it
      // We need to find the balanced braces for the record definition
      const dataTypeMatch = content.match(/type\s+alias\s+Data\s*=\s*\n?\s*/);
      if (!dataTypeMatch) {
        console.warn(`Warning: Could not find Data type definition in ${fullPath}`);
        continue;
      }

      const prefixEnd = dataTypeMatch.index + dataTypeMatch[0].length;

      // Find the matching closing brace for the record
      let braceCount = 0;
      let recordStart = -1;
      let recordEnd = -1;
      for (let i = prefixEnd; i < content.length; i++) {
        if (content[i] === '{') {
          if (recordStart === -1) recordStart = i;
          braceCount++;
        } else if (content[i] === '}') {
          braceCount--;
          if (braceCount === 0) {
            recordEnd = i + 1;
            break;
          }
        }
      }

      if (recordStart === -1 || recordEnd === -1) {
        console.warn(`Warning: Could not find balanced braces in Data type definition in ${fullPath}`);
        continue;
      }

      const currentRecord = content.substring(recordStart, recordEnd).replace(/\s+/g, " ").trim();
      const targetRecord = fix.newDataType.replace(/\s+/g, " ").trim();

      // Check if fix is already applied
      if (currentRecord === targetRecord) {
        continue; // Already fixed
      }

      // Replace the record part only
      const newContent = content.substring(0, recordStart) + fix.newDataType + content.substring(recordEnd);
      await fs.promises.writeFile(fullPath, newContent);
    } catch (e) {
      // Skip files that can't be processed
      console.warn(`Warning: Could not apply Data type fix to ${fullPath}: ${e.message}`);
    }
  }
}

/**
 * @param {string} moduleToCopy
 * @returns { Promise<void> }
 */
async function copyToBoth(moduleToCopy) {
  await Promise.all([
    copyFileEnsureDir(
      path.join(__dirname, moduleToCopy),
      path.join(`./.elm-pages/`, moduleToCopy)
    ),
    copyFileEnsureDir(
      path.join(__dirname, moduleToCopy),
      path.join(`./elm-stuff/elm-pages/client/.elm-pages`, moduleToCopy)
    ),
    copyFileEnsureDir(
      path.join(__dirname, moduleToCopy),
      path.join(`./elm-stuff/elm-pages/.elm-pages/`, moduleToCopy)
    ),
  ]);
}

/**
 * @param {string} from
 * @param {string} to
 */
async function copyFileEnsureDir(from, to) {
  await fs.promises.mkdir(path.dirname(to), {
    recursive: true,
  });
  await copyFileIfNewer(from, to);
}

/**
 * @param {string} dir
 * @returns {Promise<string[]>}
 */
async function listFiles(dir) {
  try {
    const fullDir = path.join(__dirname, dir);
    const files = await fs.promises.readdir(fullDir);
    return merge(
      await Promise.all(
        files.flatMap(async (file_) => {
          const file = path.join(dir, path.basename(file_));
          if (
            (await fs.promises.stat(path.join(__dirname, file))).isDirectory()
          ) {
            return await listFiles(file);
          } else {
            return [file];
          }
        })
      )
    );
  } catch (e) {
    return [];
  }
}

/**
 * @param {any[]} arrays
 */
function merge(arrays) {
  return [].concat.apply([], arrays);
}
