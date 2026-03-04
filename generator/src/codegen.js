import * as fs from "node:fs";
import * as fsExtra from "fs-extra";
import { rewriteElmJson } from "./rewrite-elm-json.js";
import { rewriteClientElmJson } from "./rewrite-client-elm-json.js";
import { elmPagesCliFile, elmPagesUiFile } from "./elm-file-constants.js";
import { spawn as spawnCallback } from "cross-spawn";
import { default as which } from "which";
import { generateTemplateModuleConnector } from "./generate-template-module-connector.js";

import * as path from "path";
import { ensureDirSync, deleteIfExists, writeFileIfChanged, copyFileIfNewer } from "./file-helpers.js";
import { fileURLToPath } from "url";
global.builtAt = new Date();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SOURCE_DIRECTORY_MIRROR_ROOT = ".elm-pages-source-directories";

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
 * Mirror all project source-directories into the codemod workspace so elm-review
 * fixes are applied to copied files instead of mutating the original project.
 *
 * @param {string} targetRootDir
 * @returns {Promise<Record<string, string>>}
 */
async function prepareSourceDirectoriesForCodemod(targetRootDir) {
  const elmJson = JSON.parse((await fs.promises.readFile("./elm.json")).toString());
  const sourceDirectories = Array.isArray(elmJson["source-directories"])
    ? elmJson["source-directories"]
    : [];
  /** @type {Record<string, string>} */
  const localSourceDirectories = {};
  let mirroredDirectoryIndex = 0;

  for (const sourceDirectory of sourceDirectories) {
    if (sourceDirectory === ".elm-pages") {
      continue;
    }

    const localDirectory =
      sourceDirectory === "app"
        ? "app"
        : `${SOURCE_DIRECTORY_MIRROR_ROOT}/${mirroredDirectoryIndex++}`;
    localSourceDirectories[sourceDirectory] = localDirectory;

    const sourceAbsolutePath = path.resolve(process.cwd(), sourceDirectory);
    const destinationAbsolutePath = path.join(targetRootDir, localDirectory);
    await syncElmSourceDirectory(sourceAbsolutePath, destinationAbsolutePath, {
      excludeBuildArtifacts: sourceDirectory === ".",
    });
  }

  await cleanupStaleMirroredSourceDirectories(targetRootDir, mirroredDirectoryIndex);

  return localSourceDirectories;
}

/**
 * @param {string} sourceDirectory
 * @param {string} destinationDirectory
 * @param {{excludeBuildArtifacts?: boolean}} [options]
 */
async function syncElmSourceDirectory(sourceDirectory, destinationDirectory, options = {}) {
  ensureDirSync(destinationDirectory);
  const sourceElmFiles = await listElmFiles(sourceDirectory, {
    excludeBuildArtifacts: options.excludeBuildArtifacts === true,
  });
  const sourceElmFileSet = new Set(sourceElmFiles);

  for (const relativeElmPath of sourceElmFiles) {
    const sourcePath = path.join(sourceDirectory, relativeElmPath);
    const destinationPath = path.join(destinationDirectory, relativeElmPath);
    ensureDirSync(path.dirname(destinationPath));
    await copyFileIfNewer(sourcePath, destinationPath);
  }

  const destinationElmFiles = await listElmFiles(destinationDirectory);
  for (const relativeElmPath of destinationElmFiles) {
    if (!sourceElmFileSet.has(relativeElmPath)) {
      await fs.promises.unlink(path.join(destinationDirectory, relativeElmPath));
    }
  }
}

/**
 * @param {string} baseDirectory
 * @param {{excludeBuildArtifacts?: boolean}} [options]
 * @returns {Promise<string[]>}
 */
async function listElmFiles(baseDirectory, options = {}) {
  const topLevelIgnoredNames =
    options.excludeBuildArtifacts === true
      ? new Set(["elm-stuff", "node_modules", ".git", "dist"])
      : new Set();
  return listElmFilesHelp(baseDirectory, "", topLevelIgnoredNames);
}

/**
 * @param {string} baseDirectory
 * @param {string} relativeDirectory
 * @param {Set<string>} topLevelIgnoredNames
 * @returns {Promise<string[]>}
 */
async function listElmFilesHelp(baseDirectory, relativeDirectory, topLevelIgnoredNames) {
  const absoluteDirectory =
    relativeDirectory === ""
      ? baseDirectory
      : path.join(baseDirectory, relativeDirectory);
  const entries = await fs.promises.readdir(absoluteDirectory, {
    withFileTypes: true,
  });
  const files = [];

  for (const entry of entries) {
    const relativeEntryPath =
      relativeDirectory === ""
        ? entry.name
        : path.join(relativeDirectory, entry.name);

    if (entry.isSymbolicLink()) {
      continue;
    }

    if (entry.isDirectory()) {
      if (relativeDirectory === "" && topLevelIgnoredNames.has(entry.name)) {
        continue;
      }

      files.push(
        ...(await listElmFilesHelp(
          baseDirectory,
          relativeEntryPath,
          topLevelIgnoredNames
        ))
      );
    } else if (entry.isFile() && entry.name.endsWith(".elm")) {
      files.push(relativeEntryPath);
    }
  }

  return files;
}

/**
 * @param {string} targetRootDir
 * @param {number} mirroredDirectoryCount
 */
async function cleanupStaleMirroredSourceDirectories(
  targetRootDir,
  mirroredDirectoryCount
) {
  const mirrorRootDirectory = path.join(targetRootDir, SOURCE_DIRECTORY_MIRROR_ROOT);
  ensureDirSync(mirrorRootDirectory);
  const validDirectoryNames = new Set(
    Array.from({ length: mirroredDirectoryCount }, (_, index) => String(index))
  );
  const entries = await fs.promises.readdir(mirrorRootDirectory, {
    withFileTypes: true,
  });

  for (const entry of entries) {
    if (!validDirectoryNames.has(entry.name)) {
      await fs.promises.rm(path.join(mirrorRootDirectory, entry.name), {
        recursive: true,
        force: true,
      });
    }
  }
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
  ensureDirSync("./elm-stuff/elm-pages/client/.elm-pages");
  await newCopyBoth("RouteBuilder.elm");
  await newCopyBoth("SharedTemplate.elm");
  await newCopyBoth("SiteConfig.elm");

  const localSourceDirectories = await prepareSourceDirectoriesForCodemod(
    "./elm-stuff/elm-pages/client"
  );
  await rewriteClientElmJson({ localSourceDirectories });

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
  const result = await runElmReviewCodemod("./elm-stuff/elm-pages/client/", "client", {
    localSourceDirectories,
  });
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

  const localSourceDirectories = await prepareSourceDirectoriesForCodemod(
    "./elm-stuff/elm-pages/server"
  );

  // Rewrite elm.json for server folder (3 levels deep, so need ../../../)
  await rewriteElmJson("./elm.json", "./elm-stuff/elm-pages/server/elm.json", {
    pathPrefix: "../../../",
    localSourceDirectories,
  });

  // Run server-specific elm-review codemod FIRST
  // This creates the Ephemeral type alias in Route files
  // Must run before generateTemplateModuleConnector so Main.elm can reference Ephemeral
  const serverResult = await runElmReviewCodemod(
    "./elm-stuff/elm-pages/server/",
    "server",
    { localSourceDirectories }
  );

  const shouldSkipCliEphemeralAnalysis =
    (serverResult.unsupportedHelperSeedingIssues || []).some((issue) =>
      issue.path.startsWith("app/Route/") || issue.path === "app/Shared.elm"
    );

  // When helper seeding is unsupported, server codemod fixes are skipped and
  // route modules may not expose Ephemeral aliases. Skip CLI ephemeral analysis
  // so generated Main.elm does not reference missing Route.*.Ephemeral types.
  const cliCode = await generateTemplateModuleConnector(basePath, "cli", {
    skipEphemeralAnalysis: shouldSkipCliEphemeralAnalysis,
  });

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
 * @param {{localSourceDirectories?: Record<string, string>}} [options]
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>, deOptimizationCount: number, unsupportedHelperSeedingIssues: Array<{path: string, message: string}>, codemodFixesApplied: boolean}>}
 */
export async function runElmReviewCodemod(cwd, target = "client", options = {}) {
  // Use different elm-review configs for client vs server transformations
  const configPath =
    target === "server"
      ? path.join(__dirname, "../../generator/server-review")
      : path.join(__dirname, "../../generator/dead-code-review");
  const partialFallbackConfigPath =
    target === "server"
      ? path.join(__dirname, "../../generator/server-review-partial-fallback")
      : path.join(__dirname, "../../generator/dead-code-review-partial-fallback");

  const cwdPath = path.join(process.cwd(), cwd || ".");
  const lamderaPath = await which("lamdera");

  // Run elm-review without fixes first to capture EPHEMERAL_FIELDS_JSON for analysis
  const analysisOutput = await runElmReviewCommand(cwdPath, configPath, lamderaPath, false);
  const ephemeralFields = parseEphemeralFieldsWithFields(analysisOutput);
  const deOptimizationCount = parseDeOptimizationCount(analysisOutput);
  const localToSourceDirectories = buildLocalToSourceDirectoriesLookup(
    options.localSourceDirectories || null
  );
  const unsupportedHelperSeedingIssues = parseUnsupportedHelperSeedingIssues(
    analysisOutput,
    target
  ).map((issue) => ({
    ...issue,
    localPath: normalizeIssuePath(issue.path),
    path: remapIssuePathFromMirroredSourceDirectory(
      issue.path,
      localToSourceDirectories
    ),
  }));

  if (unsupportedHelperSeedingIssues.length > 0) {
    const partialFallbackWorkspace = await createPartialFallbackConfigWorkspace(
      target,
      partialFallbackConfigPath
    );
    try {
      await syncFallbackRuleModules(target, partialFallbackWorkspace.configPath);
      const excludedPaths = await computeUnsupportedFixExclusionPaths(
        cwdPath,
        unsupportedHelperSeedingIssues
      );
      await writePartialFallbackReviewConfig(
        partialFallbackWorkspace.configPath,
        target,
        excludedPaths
      );
      await runElmReviewCommand(
        cwdPath,
        partialFallbackWorkspace.configPath,
        lamderaPath,
        true
      );
    } finally {
      await fs.promises.rm(partialFallbackWorkspace.rootPath, {
        recursive: true,
        force: true,
      });
    }
  } else {
    await runElmReviewCommand(cwdPath, configPath, lamderaPath, true);
  }

  return {
    ephemeralFields,
    deOptimizationCount,
    unsupportedHelperSeedingIssues,
    codemodFixesApplied: true,
  };
}

/**
 * @param {"client" | "server"} target
 * @param {string} fallbackConfigPath
 * @returns {Promise<{rootPath: string, configPath: string}>}
 */
async function createPartialFallbackConfigWorkspace(target, fallbackConfigPath) {
  const parentDirectory = path.dirname(fallbackConfigPath);
  const configPath = await fs.promises.mkdtemp(
    path.join(
      parentDirectory,
      `${path.basename(fallbackConfigPath)}.tmp-review-${target}-`
    )
  );
  await fs.promises.rm(configPath, { recursive: true, force: true });
  await fsExtra.copy(fallbackConfigPath, configPath);
  return { rootPath: configPath, configPath };
}

/**
 * @param {"client" | "server"} target
 * @param {string} fallbackConfigPath
 */
async function syncFallbackRuleModules(target, fallbackConfigPath) {
  const sourceRulesPath =
    target === "server"
      ? path.join(__dirname, "../../generator/server-review/src/Pages/Review")
      : path.join(__dirname, "../../generator/dead-code-review/src/Pages/Review");
  const fallbackRulesPath = path.join(fallbackConfigPath, "src", "Pages", "Review");
  await fs.promises.mkdir(fallbackRulesPath, { recursive: true });

  const sourceEntries = await fs.promises.readdir(sourceRulesPath, {
    withFileTypes: true,
  });
  const sourceElmFiles = sourceEntries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".elm"))
    .map((entry) => entry.name);
  const sourceElmFileSet = new Set(sourceElmFiles);

  for (const fileName of sourceElmFiles) {
    await copyFileIfNewer(
      path.join(sourceRulesPath, fileName),
      path.join(fallbackRulesPath, fileName)
    );
  }

  const fallbackEntries = await fs.promises.readdir(fallbackRulesPath, {
    withFileTypes: true,
  });
  for (const entry of fallbackEntries) {
    if (
      entry.isFile() &&
      entry.name.endsWith(".elm") &&
      !sourceElmFileSet.has(entry.name)
    ) {
      await fs.promises.unlink(path.join(fallbackRulesPath, entry.name));
    }
  }
}

/**
 * @param {string} cwdPath
 * @param {Array<{path: string, localPath?: string, message: string, region?: any}>} issues
 * @returns {Promise<string[]>}
 */
async function computeUnsupportedFixExclusionPaths(cwdPath, issues) {
  const sourceDirectories = await readWorkspaceSourceDirectories(cwdPath);
  const excludedPaths = new Set();
  const importingFilesCache = new Map();

  for (const issue of issues) {
    const localPath =
      issue.localPath && issue.localPath.length > 0
        ? issue.localPath
        : normalizeIssuePath(issue.path);
    if (localPath.length > 0) {
      excludedPaths.add(localPath);
    }
  }

  for (const issue of issues) {
    const issueDetails = await readUnsupportedIssueDetails(cwdPath, issue);
    const referencedHelperPath =
      await findReferencedHelperPathForUnsupportedIssue(
        cwdPath,
        sourceDirectories,
        issue,
        issueDetails
      );
    if (referencedHelperPath) {
      excludedPaths.add(referencedHelperPath);
    }

    if (
      issueDetails &&
      issueDetails.isComplexFunctionReference &&
      issueDetails.moduleName
    ) {
      const moduleName = issueDetails.moduleName;
      if (!importingFilesCache.has(moduleName)) {
        importingFilesCache.set(
          moduleName,
          await findImportingFilesForModule(
            cwdPath,
            sourceDirectories,
            moduleName
          )
        );
      }

      for (const importingPath of importingFilesCache.get(moduleName) || []) {
        excludedPaths.add(importingPath);
      }
    }
  }

  return Array.from(excludedPaths).sort();
}

/**
 * @param {string} cwdPath
 * @returns {Promise<string[]>}
 */
async function readWorkspaceSourceDirectories(cwdPath) {
  try {
    const elmJson = JSON.parse(
      (await fs.promises.readFile(path.join(cwdPath, "elm.json"))).toString()
    );
    return Array.isArray(elmJson["source-directories"])
      ? elmJson["source-directories"]
      : [];
  } catch (_error) {
    return [];
  }
}

/**
 * @param {string} cwdPath
 * @param {{path: string, localPath?: string, message: string, region?: any}} issue
 * @returns {Promise<{localPath: string, fileContent: string, regionText: string, functionReferences: Array<{qualifier: string | null, functionName: string}>, isComplexFunctionReference: boolean, moduleName: string | null} | null>}
 */
async function readUnsupportedIssueDetails(cwdPath, issue) {
  const issueLocalPath =
    issue.localPath && issue.localPath.length > 0
      ? issue.localPath
      : normalizeIssuePath(issue.path);
  if (issueLocalPath.length === 0) {
    return null;
  }

  const issueAbsolutePath = path.join(cwdPath, issueLocalPath);
  let fileContent;
  try {
    fileContent = await fs.promises.readFile(issueAbsolutePath, "utf8");
  } catch (_error) {
    return null;
  }

  const regionText =
    issue.region && issue.region.start && issue.region.end
      ? extractRegionText(fileContent, issue.region)
      : "";
  const functionReferences =
    regionText.length > 0 ? parseFunctionReferenceCandidates(regionText) : [];
  const directReference =
    regionText.length > 0 ? parseFunctionReference(regionText) : null;
  const moduleName = parseModuleNameFromElmFile(fileContent);

  return {
    localPath: issueLocalPath,
    fileContent,
    regionText,
    functionReferences,
    isComplexFunctionReference:
      functionReferences.length > 0 && directReference === null,
    moduleName,
  };
}

/**
 * @param {string} cwdPath
 * @param {string[]} sourceDirectories
 * @param {{path: string, localPath?: string, message: string, region?: any}} issue
 * @param {{localPath: string, fileContent: string, regionText: string, functionReferences: Array<{qualifier: string | null, functionName: string}>} | null} [issueDetails]
 * @returns {Promise<string | null>}
 */
async function findReferencedHelperPathForUnsupportedIssue(
  cwdPath,
  sourceDirectories,
  issue,
  issueDetails = null
) {
  const issueLocalPath = issueDetails
    ? issueDetails.localPath
    : issue.localPath && issue.localPath.length > 0
      ? issue.localPath
      : normalizeIssuePath(issue.path);
  if (issueLocalPath.length === 0) {
    return null;
  }

  let fileContent = issueDetails ? issueDetails.fileContent : null;
  if (!fileContent) {
    try {
      fileContent = await fs.promises.readFile(
        path.join(cwdPath, issueLocalPath),
        "utf8"
      );
    } catch (_error) {
      return null;
    }
  }
  const functionReferences = issueDetails
    ? issueDetails.functionReferences
    : issue.region && issue.region.start && issue.region.end
      ? parseFunctionReferenceCandidates(extractRegionText(fileContent, issue.region))
      : [];
  if (functionReferences.length === 0) {
    return null;
  }

  const imports = parseElmImports(fileContent);
  const resolvedModuleNames = new Set();
  for (const functionReference of functionReferences) {
    const helperModuleName = resolveImportedModuleName(imports, functionReference);
    if (helperModuleName) {
      resolvedModuleNames.add(helperModuleName);
    }
  }

  if (resolvedModuleNames.size !== 1) {
    return null;
  }
  const helperModuleName = Array.from(resolvedModuleNames)[0];

  const helperRelativeModulePath =
    helperModuleName.replace(/\./g, "/") + ".elm";
  for (const sourceDirectory of sourceDirectories) {
    const candidatePath = path.join(
      cwdPath,
      sourceDirectory,
      helperRelativeModulePath
    );
    if (fs.existsSync(candidatePath)) {
      return normalizeIssuePath(path.relative(cwdPath, candidatePath));
    }
  }

  return null;
}

/**
 * @param {string} fileContent
 * @returns {string | null}
 */
function parseModuleNameFromElmFile(fileContent) {
  const moduleMatch = fileContent.match(
    /^\s*module\s+([A-Z][A-Za-z0-9_.]*)\s+exposing\b/m
  );
  return moduleMatch ? moduleMatch[1] : null;
}

/**
 * @param {string} cwdPath
 * @param {string[]} sourceDirectories
 * @param {string} moduleName
 * @returns {Promise<string[]>}
 */
async function findImportingFilesForModule(cwdPath, sourceDirectories, moduleName) {
  const importingFiles = new Set();

  for (const sourceDirectory of sourceDirectories) {
    const sourceDirectoryPath = path.join(cwdPath, sourceDirectory);
    if (!fs.existsSync(sourceDirectoryPath)) {
      continue;
    }

    const elmFilePaths = await listElmFilesRecursively(sourceDirectoryPath);
    for (const elmFilePath of elmFilePaths) {
      const fileContent = await fs.promises.readFile(elmFilePath, "utf8");
      const imports = parseElmImports(fileContent);
      if (imports.byModule.has(moduleName)) {
        importingFiles.add(normalizeIssuePath(path.relative(cwdPath, elmFilePath)));
      }
    }
  }

  return Array.from(importingFiles).sort();
}

/**
 * @param {string} directoryPath
 * @returns {Promise<string[]>}
 */
async function listElmFilesRecursively(directoryPath) {
  const entries = await fs.promises.readdir(directoryPath, {
    withFileTypes: true,
  });

  const nestedFiles = await Promise.all(
    entries
      .filter((entry) => entry.isDirectory())
      .map((entry) =>
        listElmFilesRecursively(path.join(directoryPath, entry.name))
      )
  );

  const directElmFiles = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".elm"))
    .map((entry) => path.join(directoryPath, entry.name));

  return directElmFiles.concat(nestedFiles.flat());
}

/**
 * @param {string} fileContent
 * @param {{start: {line: number, column: number}, end: {line: number, column: number}}} region
 * @returns {string}
 */
function extractRegionText(fileContent, region) {
  const lines = fileContent.split(/\r?\n/);
  const startLine = region.start.line;
  const endLine = region.end.line;
  const startColumn = region.start.column;
  const endColumn = region.end.column;

  if (
    startLine <= 0 ||
    endLine <= 0 ||
    startLine > lines.length ||
    endLine > lines.length
  ) {
    return "";
  }

  if (startLine === endLine) {
    const line = lines[startLine - 1] || "";
    return line.slice(Math.max(startColumn - 1, 0), Math.max(endColumn - 1, 0));
  }

  const parts = [];
  const firstLine = lines[startLine - 1] || "";
  parts.push(firstLine.slice(Math.max(startColumn - 1, 0)));
  for (let lineIndex = startLine; lineIndex < endLine - 1; lineIndex++) {
    parts.push(lines[lineIndex] || "");
  }
  const lastLine = lines[endLine - 1] || "";
  parts.push(lastLine.slice(0, Math.max(endColumn - 1, 0)));
  return parts.join(" ").trim();
}

/**
 * @param {string} expressionText
 * @returns {{qualifier: string | null, functionName: string} | null}
 */
function parseFunctionReference(expressionText) {
  const normalizedExpression = expressionText
    .trim()
    .replace(/^\(+/, "")
    .replace(/\)+$/, "")
    .replace(/[,;]$/, "")
    .replace(/\s+/g, "");

  const qualifiedReferenceMatch = normalizedExpression.match(
    /^([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\.([a-z][A-Za-z0-9_']*)$/
  );
  if (qualifiedReferenceMatch) {
    return {
      qualifier: qualifiedReferenceMatch[1],
      functionName: qualifiedReferenceMatch[2],
    };
  }

  const unqualifiedReferenceMatch = normalizedExpression.match(
    /^([a-z][A-Za-z0-9_']*)$/
  );
  if (unqualifiedReferenceMatch) {
    return {
      qualifier: null,
      functionName: unqualifiedReferenceMatch[1],
    };
  }

  return null;
}

/**
 * @param {string} expressionText
 * @returns {Array<{qualifier: string | null, functionName: string}>}
 */
function parseFunctionReferenceCandidates(expressionText) {
  const normalizedExpression = expressionText.trim();
  if (normalizedExpression.length === 0) {
    return [];
  }

  const candidates = [];
  const candidateKeys = new Set();
  const addCandidate = (candidate) => {
    const key = `${candidate.qualifier || ""}|${candidate.functionName}`;
    if (!candidateKeys.has(key)) {
      candidateKeys.add(key);
      candidates.push(candidate);
    }
  };

  const directReference = parseFunctionReference(normalizedExpression);
  if (directReference) {
    addCandidate(directReference);
  }

  // Complex expressions (for example partial application/composition) can still
  // contain a module-qualified helper reference somewhere inside.
  const qualifiedReferencePattern =
    /([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\.([a-z][A-Za-z0-9_']*)/g;
  for (const match of normalizedExpression.matchAll(qualifiedReferencePattern)) {
    addCandidate({
      qualifier: match[1],
      functionName: match[2],
    });
  }

  return candidates;
}

/**
 * @param {string} fileContent
 * @returns {{byAlias: Map<string, string>, byModule: Set<string>, imports: Array<{moduleName: string, exposesAll: boolean, exposedValues: Set<string>}>}}
 */
function parseElmImports(fileContent) {
  const byAlias = new Map();
  const byModule = new Set();
  const imports = [];
  const importPattern =
    /(?:^|\n)\s*import\s+([A-Z][A-Za-z0-9_.]*)(?:\s+as\s+([A-Z][A-Za-z0-9_]*))?(?:\s+exposing\s*\(([\s\S]*?)\))?/g;

  for (const importMatch of fileContent.matchAll(importPattern)) {
    const moduleName = importMatch[1];
    const alias = importMatch[2] || null;
    const exposingClause = importMatch[3] || null;
    byModule.add(moduleName);
    if (alias) {
      byAlias.set(alias, moduleName);
    }

    const exposingTokens =
      exposingClause === null
        ? []
        : exposingClause
            .split(",")
            .map((token) => token.trim())
            .filter((token) => token.length > 0);
    const exposesAll = exposingTokens.includes("..");
    const exposedValues = new Set(
      exposingTokens.filter((token) => /^[a-z][A-Za-z0-9_']*$/.test(token))
    );
    imports.push({ moduleName, exposesAll, exposedValues });
  }

  return { byAlias, byModule, imports };
}

/**
 * @param {{byAlias: Map<string, string>, byModule: Set<string>, imports: Array<{moduleName: string, exposesAll: boolean, exposedValues: Set<string>}>}} imports
 * @param {{qualifier: string | null, functionName: string}} functionReference
 * @returns {string | null}
 */
function resolveImportedModuleName(imports, functionReference) {
  if (functionReference.qualifier !== null) {
    const qualifier = functionReference.qualifier;
    if (imports.byAlias.has(qualifier)) {
      return imports.byAlias.get(qualifier) || null;
    }

    if (imports.byModule.has(qualifier)) {
      return qualifier;
    }

    return null;
  }

  const matchingImports = imports.imports
    .filter(
      (importEntry) =>
        importEntry.exposesAll ||
        importEntry.exposedValues.has(functionReference.functionName)
    )
    .map((importEntry) => importEntry.moduleName);

  if (matchingImports.length === 1) {
    return matchingImports[0];
  }

  return null;
}

/**
 * @param {string} fallbackConfigPath
 * @param {"client" | "server"} target
 * @param {string[]} excludedPaths
 */
async function writePartialFallbackReviewConfig(
  fallbackConfigPath,
  target,
  excludedPaths
) {
  const reviewConfigPath = path.join(fallbackConfigPath, "src", "ReviewConfig.elm");
  const excludedPathsLiteral = toElmStringList(excludedPaths);
  const isIncludedDefinition = `excludedPaths : List String
excludedPaths =
${excludedPathsLiteral}


isIncluded : String -> Bool
isIncluded path =
    not (List.member path excludedPaths)
`;

  const reviewConfigContent =
    target === "server"
      ? `module ReviewConfig exposing (config)

import Pages.Review.ServerDataTransform
import Review.Rule as Rule exposing (Rule)


${isIncludedDefinition}

config : List Rule
config =
    [ Pages.Review.ServerDataTransform.rule
        |> Rule.filterErrorsForFiles isIncluded
    ]
`
      : `module ReviewConfig exposing (config)

import Pages.Review.DeadCodeEliminateData
import Pages.Review.StaticViewTransform
import Review.Rule as Rule exposing (Rule)


${isIncludedDefinition}

config : List Rule
config =
    [ Pages.Review.DeadCodeEliminateData.rule
        |> Rule.filterErrorsForFiles (\\path -> String.startsWith "app/" path && isIncluded path)
    , Pages.Review.StaticViewTransform.rule
        |> Rule.filterErrorsForFiles isIncluded
    ]
`;

  await fs.promises.writeFile(reviewConfigPath, reviewConfigContent);
}

/**
 * @param {string[]} values
 * @returns {string}
 */
function toElmStringList(values) {
  if (values.length === 0) {
    return "    []";
  }

  return `    [ ${values
    .map((value) => `"${escapeElmString(value)}"`)
    .join("\n    , ")}
    ]`;
}

/**
 * @param {string} value
 * @returns {string}
 */
function escapeElmString(value) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

/**
 * @param {Record<string, string> | null} localSourceDirectories
 * @returns {Array<{sourceDirectory: string, localDirectory: string}>}
 */
function buildLocalToSourceDirectoriesLookup(localSourceDirectories) {
  if (!localSourceDirectories) {
    return [];
  }

  return Object.entries(localSourceDirectories)
    .map(([sourceDirectory, localDirectory]) => ({
      sourceDirectory: normalizeIssuePath(sourceDirectory),
      localDirectory: normalizeIssuePath(localDirectory),
    }))
    .sort((left, right) => right.localDirectory.length - left.localDirectory.length);
}

/**
 * @param {string} issuePath
 * @param {Array<{sourceDirectory: string, localDirectory: string}>} localToSourceDirectories
 * @returns {string}
 */
function remapIssuePathFromMirroredSourceDirectory(
  issuePath,
  localToSourceDirectories
) {
  const normalizedIssuePath = normalizeIssuePath(issuePath);

  for (const mapping of localToSourceDirectories) {
    if (mapping.localDirectory === "") {
      continue;
    }

    if (normalizedIssuePath === mapping.localDirectory) {
      return mapping.sourceDirectory;
    }

    if (normalizedIssuePath.startsWith(mapping.localDirectory + "/")) {
      return (
        mapping.sourceDirectory +
        normalizedIssuePath.slice(mapping.localDirectory.length)
      );
    }
  }

  return normalizedIssuePath;
}

/**
 * @param {string} inputPath
 * @returns {string}
 */
function normalizeIssuePath(inputPath) {
  return inputPath
    .replace(/\\/g, "/")
    .replace(/^\.\/+/, "")
    .replace(/\/+$/, "");
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
 * @returns {Array<{path: string, message: string, region?: any}>}
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
          region: error.region || null,
        });
      }
    }
  }

  return issues;
}

export const __testHelpers = {
  computeUnsupportedFixExclusionPaths,
  findReferencedHelperPathForUnsupportedIssue,
  extractRegionText,
  parseFunctionReference,
  parseFunctionReferenceCandidates,
  parseElmImports,
  resolveImportedModuleName,
};

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
