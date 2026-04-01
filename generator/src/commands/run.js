/**
 * Run command - runs an elm-pages script.
 */

import * as fs from "node:fs";
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
      let userSourceDirs = await getUserSourceDirs(projectDirectory);

      // Apply --coverage-include / --coverage-exclude filters
      const include = options.coverageInclude || [];
      const exclude = options.coverageExclude || [];
      if (include.length > 0) {
        userSourceDirs = userSourceDirs.filter((d) =>
          include.some((inc) => path.normalize(d) === path.normalize(inc))
        );
      }
      if (exclude.length > 0) {
        userSourceDirs = userSourceDirs.filter((d) =>
          !exclude.some((exc) => path.normalize(d) === path.normalize(exc))
        );
      }

      if (userSourceDirs.length === 0) {
        console.warn("Warning: No user source directories found to instrument.");
      } else {
        try {
          const result = await setupCoverage(
            projectDirectory,
            userSourceDirs,
            compileDir
          );
          coverageDataDir = result.coverageDir;
        } catch (e) {
          // Coverage setup failed (elm-instrument missing, parse error, etc.)
          // Run the script normally without coverage instead of crashing.
          console.warn(`Warning: Coverage instrumentation failed. Running without coverage.\n  ${e.message || e}`);
        }
      }

      // Clean stale coverage output so a failed run doesn't leave old data
      try {
        const staleLcov = path.join(process.cwd(), "coverage", "lcov.info");
        if (fs.existsSync(staleLcov)) fs.unlinkSync(staleLcov);
      } catch {}

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

    // Force recompile when coverage instrumentation succeeded (sources differ)
    const shouldRecompile =
      (coverage && coverageDataDir) ||
      (await needsRecompilation(projectDirectory, outputPath));

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
    if (coverage && coverageDataDir) {
      const { printCoverageReportSync } = await import("../coverage.js");
      const outputCwd = cwd; // where the user ran the command
      const moduleFilter = {
        include: options.coverageIncludeModule || [],
        exclude: options.coverageExcludeModule || [],
      };
      process.on("exit", () => {
        printCoverageReportSync(projectDirectory, outputCwd, moduleFilter);
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
