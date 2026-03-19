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
    writeFileIfChanged("./.elm-pages/TestApp.elm", browserCode.testAppModule),
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
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>, deOptimizationCount: number}>}
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
  // Force-copy app files (not copyDirIfNewer) because the codemod modifies these files,
  // making their mtime newer than the source. On subsequent builds, copyDirIfNewer would
  // skip copying and the analysis would run on already-transformed files.
  await fsExtra.copy("./app", "./elm-stuff/elm-pages/client/app", { overwrite: true });

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
  return { ephemeralFields: result.ephemeralFields, deOptimizationCount: result.deOptimizationCount || 0 };
}

/**
 * Scan route files to find which ones actually contain `type alias Ephemeral`.
 * This is the ground truth — regardless of what elm-review's analysis reported,
 * we only reference Ephemeral in Main.elm if it actually exists in the file.
 * @param {string} routeDir - path to the Route directory (e.g., "./elm-stuff/elm-pages/server/app/Route")
 * @returns {Promise<string[]>} - module names like "Route.Index", "Route.Page_"
 */
async function verifyEphemeralTypesExist(routeDir) {
  const result = [];

  async function scanDir(dir, modulePrefix) {
    let entries;
    try {
      entries = await fs.promises.readdir(dir, { withFileTypes: true });
    } catch (e) {
      return;
    }
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        await scanDir(fullPath, modulePrefix + entry.name + ".");
      } else if (entry.name.endsWith(".elm")) {
        const moduleName = modulePrefix + entry.name.slice(0, -4);
        try {
          const content = await fs.promises.readFile(fullPath, "utf8");
          if (content.includes("type alias Ephemeral")) {
            result.push(moduleName);
          }
        } catch (e) {
          // Skip unreadable files
        }
      }
    }
  }

  await scanDir(routeDir, "Route.");
  return result;
}

/**
 * Generate the server folder with server-specific codemods.
 * @param {string} basePath
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>}>}
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

  // Force-copy app files (not copyDirIfNewer) because the codemod modifies these files,
  // making their mtime newer than the source. On subsequent builds, copyDirIfNewer would
  // skip copying and the analysis would run on already-transformed files.
  await fsExtra.copy("./app", "./elm-stuff/elm-pages/server/app", { overwrite: true });

  // Generate temporary Route.elm, Pages.elm, and Fetcher modules BEFORE the codemod.
  // elm-review needs to compile the project to set up ModuleNameLookupTable, and many
  // app modules (Shared.elm, Route modules, etc.) import the generated Route module.
  // Without these files, elm-review silently fails to apply Ephemeral type fixes.
  const tempBrowserCode = await generateTemplateModuleConnector(basePath, "browser");
  await writeFileIfChanged(
    "./elm-stuff/elm-pages/server/.elm-pages/Route.elm",
    tempBrowserCode.routesModule
  );
  await writeFileIfChanged(
    "./elm-stuff/elm-pages/server/.elm-pages/Pages.elm",
    elmPagesCliFile()
  );
  await writeFetcherModules(
    "./elm-stuff/elm-pages/server/.elm-pages",
    tempBrowserCode.fetcherModules
  );

  // Run server-specific elm-review codemod
  // This creates the Ephemeral type alias in Route files
  // Must run before generateTemplateModuleConnector so Main.elm can reference Ephemeral
  const serverResult = await runElmReviewCodemod("./elm-stuff/elm-pages/server/", "server");

  // Verify which route files ACTUALLY have the Ephemeral type after the codemod.
  // Don't trust the analysis output alone — the fix-application step may fail silently.
  // Only reference Ephemeral types in Main.elm if they actually exist in the files.
  const routesWithEphemeral = await verifyEphemeralTypesExist(
    "./elm-stuff/elm-pages/server/app/Route"
  );
  if (serverResult.ephemeralFields.size > 0 && routesWithEphemeral.length === 0) {
    console.log(`[elm-pages] WARNING: elm-review analysis found ${serverResult.ephemeralFields.size} routes with ephemeral fields, but no Ephemeral types were found in the output files. The Ephemeral type optimization will be skipped.`);
  }
  const cliCode = await generateTemplateModuleConnector(basePath, "cli", { routesWithEphemeral });

  // Write final generated Main.elm, Route.elm, Pages.elm (overwriting the temporary ones)
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

  return { ephemeralFields: serverResult.ephemeralFields };
}

/**
 * Resolve the path to elm-format, checking PATH then node_modules/.bin/.
 * @returns {Promise<string|null>}
 */
async function resolveElmFormat() {
  try {
    return await which("elm-format");
  } catch (e) {
    // Not on PATH — check node_modules/.bin/ as fallback
    // (elm-tooling installs here, but it may not be on PATH in all environments)
    const localPath = path.join(process.cwd(), "node_modules", ".bin", "elm-format");
    try {
      await fs.promises.access(localPath, fs.constants.X_OK);
      return localPath;
    } catch (e2) {
      return null;
    }
  }
}

export async function runElmReviewCodemod(cwd, target = "client") {
  // Use different elm-review configs for client vs server transformations
  const configPath =
    target === "server"
      ? path.join(__dirname, "../../generator/server-review")
      : path.join(__dirname, "../../generator/dead-code-review");

  const cwdPath = path.join(process.cwd(), cwd || ".");
  const lamderaPath = await which("lamdera");
  const elmFormatPath = await resolveElmFormat();

  // Run elm-review without fixes first to capture EPHEMERAL_FIELDS_JSON for analysis.
  // This step does not require elm-format.
  const analysisOutput = await runElmReviewCommand(cwdPath, configPath, lamderaPath, elmFormatPath, false);
  const ephemeralFields = parseEphemeralFieldsWithFields(analysisOutput);
  const deOptimizationCount = parseDeOptimizationCount(analysisOutput);

  // Apply fixes. elm-review requires elm-format for this step.
  if (elmFormatPath) {
    await runElmReviewCommand(cwdPath, configPath, lamderaPath, elmFormatPath, true);
  } else {
    console.log(
      `[elm-pages] elm-format not found. Skipping Ephemeral type optimization.\n` +
      `Install elm-format (e.g., via elm-tooling) to enable this optimization.`
    );
  }

  return { ephemeralFields, deOptimizationCount };
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
 * Run elm-review command
 * @param {string} cwdPath
 * @param {string} configPath
 * @param {string} lamderaPath
 * @param {boolean} applyFixes
 */
async function runElmReviewCommand(cwdPath, configPath, lamderaPath, elmFormatPath, applyFixes) {
  const args = [
    "--report", "json",
    "--namespace", "elm-pages",
    "--config", configPath,
    "--elmjson", "elm.json",
    "--compiler", lamderaPath,
  ];
  if (elmFormatPath) {
    args.push("--elm-format-path", elmFormatPath);
  }
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
      if (code === 0 || !applyFixes) {
        // For analysis-only run, exit code 1 is expected (errors found)
        resolve(stdout);
      } else {
        // Non-zero exit during fix application. Check if it's a real elm-review
        // error (type: "error") or just a benign failing fix (type: "review-errors").
        let isRealError = false;
        try {
          const parsed = JSON.parse(stdout);
          // elm-review uses type: "error" for tool-level failures
          // (e.g., ELM-FORMAT NOT FOUND, CONFIGURATION ERROR)
          // and type: "review-errors" for rule results (including failing fixes).
          isRealError = parsed.type === "error";
        } catch (e) {
          // Couldn't parse JSON — treat unparseable output as a real error
          isRealError = true;
        }
        if (isRealError) {
          reject(stdout + stderr);
        } else {
          // Benign: fix already applied or no fixes needed
          resolve(stdout);
        }
      }
    });
  });
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
