/**
 * Run command - runs an elm-pages script.
 */

import * as path from "node:path";
import * as url from "node:url";
import * as esbuild from "esbuild";
import * as globby from "globby";
import * as renderer from "../render.js";
import { compileCliApp } from "../compile-elm.js";
import { resolveInputPathOrModuleName } from "../resolve-elm-module.js";
import { restoreColorSafe } from "../error-formatter.js";
import {
  needsRecompilation,
  needsPortsRecompilation,
  updateVersionMarker,
} from "../script-cache.js";
import { compileElmForScript, requireElm, printCaughtError } from "./shared.js";

export async function run(elmModulePath, options, options2) {
  const unprocessedCliOptions = options2.args.splice(
    options2.processedArgs.length,
    options2.args.length
  );
  try {
    const { moduleName, projectDirectory, sourceDirectory } =
      await resolveInputPathOrModuleName(elmModulePath);
    await compileElmForScript(elmModulePath, {
      moduleName,
      projectDirectory,
      sourceDirectory,
    });

    // Check if custom-backend-task needs recompilation
    const portsCheck = await needsPortsRecompilation(projectDirectory);
    let portsPath = portsCheck.outputPath;

    if (portsCheck.needed) {
      const portBackendTaskCompiled = esbuild
        .build({
          entryPoints: [
            path.resolve(projectDirectory, "./custom-backend-task"),
          ],
          platform: "node",
          outfile: path.resolve(
            projectDirectory,
            ".elm-pages/compiled-ports/custom-backend-task.mjs"
          ),
          assetNames: "[name]-[hash]",
          chunkNames: "chunks/[name]-[hash]",
          metafile: true,
          bundle: true,
          format: "esm",
          packages: "external",
          logLevel: "silent",
        })
        .then((result) => {
          try {
            return Object.keys(result.metafile.outputs)[0];
          } catch (e) {
            return null;
          }
        })
        .catch((error) => {
          const portBackendTaskFileFound =
            globby.globbySync(
              path.resolve(projectDirectory, "./custom-backend-task.*")
            ).length > 0;
          if (portBackendTaskFileFound) {
            // don't present error if there are no files matching custom-backend-task
            // if there are files matching custom-backend-task, warn the user in case something went wrong loading it
            console.error("Failed to load custom-backend-task file.", error);
          }

          return undefined;
        });
      portsPath = await portBackendTaskCompiled;
    }

    const cwd = process.cwd();
    process.chdir(projectDirectory);
    // TODO have option for compiling with --debug or not (maybe allow running with elm-optimize-level-2 as well?)

    const outputPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/elm.cjs"
    );
    const shouldRecompile = await needsRecompilation(
      projectDirectory,
      outputPath
    );

    if (shouldRecompile) {
      const elmEntrypointPath = path.join(
        projectDirectory,
        "elm-stuff/elm-pages/.elm-pages/ScriptMain.elm"
      );
      const elmOutputPath = path.join(
        projectDirectory,
        "elm-stuff/elm-pages/elm.js"
      );
      await compileCliApp(
        { debug: true },
        elmEntrypointPath,
        elmOutputPath,
        path.join(projectDirectory, "elm-stuff/elm-pages"),
        elmOutputPath
      );
      await updateVersionMarker(projectDirectory);
    }
    process.chdir(cwd);
    await renderer.runGenerator(
      unprocessedCliOptions,
      portsPath
        ? await import(url.pathToFileURL(path.resolve(portsPath)).href)
        : null,
      await requireElm(`${projectDirectory}/elm-stuff/elm-pages/elm.cjs`),
      moduleName
    );
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}
