/**
 * Run command - runs an elm-pages script.
 */

import * as path from "node:path";
import * as url from "node:url";
import * as renderer from "../render.js";
import { resolveInputPathOrModuleName } from "../resolve-elm-module.js";
import { restoreColorSafe } from "../error-formatter.js";
import {
  needsRecompilation,
  needsPortsRecompilation,
  updateVersionMarker,
} from "../script-cache.js";
import {
  compileElmForScript,
  hasReservedCliFlag,
  requireElm,
  printCaughtError,
} from "./shared.js";
import { scriptUsesPagesDb } from "../db-usage.js";

export async function run(elmModulePath, options, options2) {
  if (elmModulePath === "--help" || elmModulePath === "-h") {
    options2.outputHelp();
    return;
  }
  const unprocessedCliOptions = options2.args.splice(
    options2.processedArgs.length,
    options2.args.length
  );
  const isIntrospectionRun = hasReservedCliFlag(
    unprocessedCliOptions,
    "--introspect-cli"
  );
  const coverage = options.coverage || false;

  try {
    const { moduleName, projectDirectory, sourceDirectory } =
      await resolveInputPathOrModuleName(elmModulePath);

    // Detect if this script uses the built-in database directly or transitively.
    const usesDb = await scriptUsesPagesDb({
      projectDirectory,
      sourceDirectory,
      entryModuleName: moduleName,
    });

    await compileElmForScript(
      elmModulePath,
      { moduleName, projectDirectory, sourceDirectory },
      { usesDb }
    );

    // ── Coverage: instrument sources and redirect compilation ──
    let coverageDataDir;
    if (coverage) {
      const {
        getUserSourceDirs,
        setupCoverage,
      } = await import("../coverage.js");

      const compileDir = path.join(projectDirectory, "elm-stuff/elm-pages");
      const userSourceDirs = await getUserSourceDirs(projectDirectory);

      if (userSourceDirs.length === 0) {
        console.warn("Warning: No user source directories found to instrument.");
      } else {
        const result = await setupCoverage(
          projectDirectory,
          userSourceDirs,
          compileDir
        );
        coverageDataDir = result.coverageDir;
      }
    }

    // Check if custom-backend-task needs recompilation
    const portsCheck = await needsPortsRecompilation(projectDirectory);
    let portsPath = portsCheck.outputPath;

    if (portsCheck.needed) {
      const [esbuild, globby] = await Promise.all([
        import("esbuild"),
        import("globby"),
      ]);
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
            console.error("Failed to load custom-backend-task file.", error);
          }
        });
      portsPath = await portBackendTaskCompiled;
    }

    const cwd = process.cwd();
    process.chdir(projectDirectory);

    const outputPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/elm.cjs"
    );

    // Always recompile when coverage is enabled (instrumented sources differ)
    const shouldRecompile =
      coverage || (await needsRecompilation(projectDirectory, outputPath));

    if (shouldRecompile) {
      const elmEntrypointPath = path.join(
        projectDirectory,
        "elm-stuff/elm-pages/.elm-pages/ScriptMain.elm"
      );
      const elmOutputPath = path.join(
        projectDirectory,
        "elm-stuff/elm-pages/elm.js"
      );
      const { compileCliApp } = await import("../compile-elm.js");
      await compileCliApp(
        { debug: true },
        elmEntrypointPath,
        elmOutputPath,
        path.join(projectDirectory, "elm-stuff/elm-pages"),
        elmOutputPath
      );

      // ── Coverage: inject tracking code into compiled JS ──
      if (coverage && coverageDataDir) {
        const { injectCoverageTracking } = await import("../coverage.js");
        await injectCoverageTracking(outputPath, coverageDataDir);
      }

      await updateVersionMarker(projectDirectory);
    }
    process.chdir(cwd);

    // Load the compiled Elm module first so the coverage data-writing
    // exit handler (injected in the JS) is registered.
    const elmModule = await requireElm(
      `${projectDirectory}/elm-stuff/elm-pages/elm.cjs`,
      { suppressConsoleLog: isIntrospectionRun }
    );

    // ── Coverage: register report handler AFTER elm module loads ──
    // The script calls process.exit(0) which prevents async code from
    // running after runGenerator. A synchronous "exit" handler registered
    // after the elm module's data-writing handler ensures correct ordering.
    if (coverage) {
      const { printCoverageReportSync } = await import("../coverage.js");
      process.on("exit", () => {
        printCoverageReportSync(projectDirectory);
      });
    }

    await renderer.runGenerator(
      unprocessedCliOptions,
      portsPath
        ? await import(url.pathToFileURL(path.resolve(portsPath)).href)
        : null,
      elmModule,
      moduleName,
      undefined,
      { suppressConsoleLogDuringInit: isIntrospectionRun }
    );
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}
