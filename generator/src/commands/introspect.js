/**
 * Introspect command - batch-discovers scripts and returns metadata for the
 * ones whose `run` value uses Script.withSchema, outputting combined JSON.
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
  moduleExposesValue,
  printCaughtError,
} from "./shared.js";
import { filePathToModuleName } from "../resolve-elm-module.js";

/**
 * Find all candidate script modules and generate a batch introspection module.
 */
export async function run() {
  try {
    const { projectDirectory, sourceDirectories } = resolveScriptDirectories();

    const scripts = findIntrospectableScripts(sourceDirectories);

    if (scripts.length === 0) {
      console.log("[]");
      return;
    }

    // Write the batch introspection wrapper
    const [
      { ensureDirSync, writeFileIfChanged, syncFilesToDirectory },
      globby,
      { rewriteElmJson },
    ] = await Promise.all([
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
      await requireElm(outputPath, { suppressConsoleLog: true }),
      "IntrospectAll",
      undefined,
      { suppressConsoleLogDuringInit: true }
    );
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}

/**
 * Recursively find all .elm files that expose `run` and return module names.
 */
function findIntrospectableScripts(sourceDirs) {
  const modules = [];
  for (const sourceDir of sourceDirs) {
    findElmFilesRecursive(sourceDir, sourceDir, modules);
  }
  return modules;
}

function findElmFilesRecursive(baseDir, currentDir, results) {
  const entries = fs.readdirSync(currentDir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(currentDir, entry.name);
    if (entry.isDirectory()) {
      findElmFilesRecursive(baseDir, fullPath, results);
    } else if (entry.name.endsWith(".elm")) {
      if (
        moduleExposesValue(fullPath, "run") &&
        moduleImportsPagesScript(fullPath)
      ) {
        const relativePath = path.relative(baseDir, fullPath);
        const moduleName = filePathToModuleName(relativePath);
        // Path relative to where `elm-pages introspect` is run
        const scriptPath = path.relative(process.cwd(), fullPath);
        results.push({ moduleName, path: scriptPath });
      }
    }
  }
}

function moduleImportsPagesScript(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8").includes("Pages.Script");
  } catch (_) {
    return false;
  }
}

/**
 * Resolve the script project and local source directories.
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
  const sourceDirectories = srcDirs
    .filter((d) => !d.startsWith("..") && d !== ".elm-pages")
    .map((dir) => path.resolve(projectDirectory, dir));

  if (sourceDirectories.length === 0) {
    console.error("No local source directories found.");
    process.exit(1);
  }

  const missingSourceDirectory = sourceDirectories.find(
    (dir) => !fs.existsSync(dir)
  );

  if (missingSourceDirectory) {
    console.error(`Source directory ${missingSourceDirectory} not found.`);
    process.exit(1);
  }

  return { projectDirectory, sourceDirectories };
}
