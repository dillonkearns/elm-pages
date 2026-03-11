/**
 * Introspect command - batch-discovers all scripts using Script.withSchema
 * and outputs their combined introspection JSON.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as renderer from "../render.js";
import { compileCliApp } from "../compile-elm.js";
import { restoreColorSafe } from "../error-formatter.js";
import {
  requireElm,
  requireLamdera,
  introspectWrapperFile,
  printCaughtError,
} from "./shared.js";
import { filePathToModuleName } from "../resolve-elm-module.js";

/**
 * Find all .elm files in script/src/ and generate a batch introspection module.
 */
export async function run() {
  try {
    const { projectDirectory, sourceDirectory } = resolveScriptDirectories();

    const scripts = findScriptModules(sourceDirectory);

    if (scripts.length === 0) {
      console.log("[]");
      return;
    }

    // Write the batch introspection wrapper
    const [{ ensureDirSync, writeFileIfChanged, syncFilesToDirectory }, globby, { rewriteElmJson }] =
      await Promise.all([
        import("../file-helpers.js"),
        import("globby"),
        import("../rewrite-elm-json.js"),
      ]);

    ensureDirSync(`${projectDirectory}/elm-stuff`);
    ensureDirSync(`${projectDirectory}/elm-stuff/elm-pages/.elm-pages`);

    await writeFileIfChanged(
      path.join(
        `${projectDirectory}/elm-stuff/elm-pages/.elm-pages/ScriptMain.elm`
      ),
      introspectWrapperFile(scripts)
    );

    await requireLamdera();

    // Copy .elm files from project root to parentDirectory
    const elmFiles = globby.globbySync(`${projectDirectory}/*.elm`);
    await syncFilesToDirectory(
      elmFiles,
      `${projectDirectory}/elm-stuff/elm-pages/parentDirectory`,
      (file) => path.basename(file)
    );

    await rewriteElmJson(
      `${projectDirectory}/elm.json`,
      `${projectDirectory}/elm-stuff/elm-pages/elm.json`,
      {}
    );

    const elmEntrypointPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/.elm-pages/ScriptMain.elm"
    );
    const elmOutputPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/elm.js"
    );
    const outputPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/elm.cjs"
    );

    await compileCliApp(
      { debug: true },
      elmEntrypointPath,
      elmOutputPath,
      path.join(projectDirectory, "elm-stuff/elm-pages"),
      elmOutputPath
    );

    await renderer.runGenerator(
      [],
      null,
      await requireElm(outputPath),
      "IntrospectAll"
    );
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}

/**
 * Recursively find all .elm files that expose `run` and return module names.
 */
function findScriptModules(sourceDir) {
  const modules = [];
  findElmFilesRecursive(sourceDir, sourceDir, modules);
  return modules;
}

function findElmFilesRecursive(baseDir, currentDir, results) {
  const entries = fs.readdirSync(currentDir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(currentDir, entry.name);
    if (entry.isDirectory()) {
      findElmFilesRecursive(baseDir, fullPath, results);
    } else if (entry.name.endsWith(".elm")) {
      if (moduleExposesRun(fullPath)) {
        const relativePath = path.relative(baseDir, fullPath);
        const moduleName = filePathToModuleName(relativePath);
        // Path relative to where `elm-pages introspect` is run
        const scriptPath = path.relative(process.cwd(), fullPath);
        results.push({ moduleName, path: scriptPath });
      }
    }
  }
}

/**
 * Resolve the script project and source directories.
 * Standard elm-pages layout: script/elm.json with script/src/
 * Fallback: ./elm.json with its source-directories
 */
function resolveScriptDirectories() {
  const elmJsonPath = fs.existsSync("./script/elm.json")
    ? "./script/elm.json"
    : fs.existsSync("./elm.json")
      ? "./elm.json"
      : null;

  if (!elmJsonPath) {
    console.error("No elm.json found.");
    process.exit(1);
  }

  const projectDirectory = path.resolve(path.dirname(elmJsonPath));
  const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
  const srcDirs = elmJson["source-directories"] || ["src"];
  const sourceDirectory = path.resolve(
    projectDirectory,
    srcDirs.find((d) => !d.startsWith("..") && d !== ".elm-pages") || "src"
  );

  if (!fs.existsSync(sourceDirectory)) {
    console.error(`Source directory ${sourceDirectory} not found.`);
    process.exit(1);
  }

  return { projectDirectory, sourceDirectory };
}

/**
 * Quick check if an Elm module exposes `run` by scanning the module declaration.
 */
function moduleExposesRun(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  // Match the exposing clause in the module declaration
  const match = content.match(
    /^module\s+\S+\s+exposing\s*\(([\s\S]*?)\)/m
  );
  if (!match) return false;
  const exposing = match[1];
  // Check for `run` as a standalone name (not part of another name)
  return /(?:^|[,\s])run(?:$|[,\s])/.test(exposing) || exposing.trim() === "..";
}
