/**
 * Test command - runs a TUI test module through the interactive stepper.
 *
 * Looks for a `stepper` export in the given Elm module (a TuiTest pipeline),
 * generates a ScriptMain that wraps it with Tui.Test.Stepper.run, and runs
 * the result as an interactive TUI.
 *
 * Usage: elm-pages test tests/TuiTests.elm
 *        elm-pages test script/src/MyTuiTest.elm
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
  needsPortsRecompilation,
  updateVersionMarker,
} from "../script-cache.js";
import {
  compileElmForScript,
  requireElm,
  printCaughtError,
  findTuiTestValues,
  testStepperWrapperFile,
} from "./shared.js";

export async function run(elmModulePath, options, options2) {
  if (elmModulePath === "--help" || elmModulePath === "-h") {
    console.log(
      "Usage: elm-pages test <path-to-module>\n\n" +
        "Run a TUI test through the interactive stepper.\n" +
        'The module must export a `stepper` value of type `TuiTest model msg`.\n\n' +
        "Example:\n" +
        "  elm-pages test tests/MyTuiTest.elm\n"
    );
    return;
  }

  try {
    const { moduleName, projectDirectory, sourceDirectory } =
      await resolveInputPathOrModuleName(elmModulePath);

    // Find all exposed TuiTest values by scanning type annotations
    const fullPath = path.resolve(
      sourceDirectory,
      moduleName.replace(/\./g, "/") + ".elm"
    );

    const tuiTestValues = findTuiTestValues(fullPath);

    if (tuiTestValues.length === 0) {
      console.error(
        `Error: No TuiTest values found in ${moduleName}.\n\n` +
          "elm-pages test discovers exposed values with a TuiTest type annotation.\n" +
          "Add a type annotation to your test pipeline:\n\n" +
          `    myTest : TuiTest.TuiTest Model Msg\n` +
          `    myTest =\n` +
          `        TuiTest.start { ... }\n` +
          `            |> TuiTest.pressKey 'j'\n`
      );
      process.exit(1);
    }

    console.log(
      `Found ${tuiTestValues.length} TuiTest value${tuiTestValues.length > 1 ? "s" : ""}: ${tuiTestValues.join(", ")}`
    );

    // Generate stepper wrapper
    const [{ ensureDirSync, writeFileIfChanged }] = await Promise.all([
      import("../file-helpers.js"),
    ]);

    ensureDirSync(`${projectDirectory}/elm-stuff/elm-pages/.elm-pages`);

    await writeFileIfChanged(
      path.join(
        `${projectDirectory}/elm-stuff/elm-pages/.elm-pages/ScriptMain.elm`
      ),
      testStepperWrapperFile(moduleName, tuiTestValues)
    );

    // Compile (reuses the same pipeline as `run`)
    await compileElmForScript(
      elmModulePath,
      { moduleName, projectDirectory, sourceDirectory },
      { usesDb: false }
    );

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
        .catch(() => null);
      portsPath = await portBackendTaskCompiled;
    }

    const cwd = process.cwd();
    process.chdir(projectDirectory);

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

    process.chdir(cwd);
    await renderer.runGenerator(
      [],
      portsPath
        ? await import(url.pathToFileURL(path.resolve(portsPath)).href)
        : null,
      await requireElm(`${projectDirectory}/elm-stuff/elm-pages/elm.cjs`),
      moduleName + ".Stepper",
      undefined,
      {}
    );
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}
