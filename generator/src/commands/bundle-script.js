/**
 * Bundle-script command - bundles an elm-pages script for distribution.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";
import * as esbuild from "esbuild";
import * as globby from "globby";
import { compileCliApp } from "../compile-elm.js";
import { resolveInputPathOrModuleName } from "../resolve-elm-module.js";
import { restoreColorSafe } from "../error-formatter.js";
import { compileElmForScript, printCaughtError } from "./shared.js";
import { scriptUsesPagesDb } from "../db-usage.js";
import { needsPortsRecompilation } from "../script-cache.js";

const __filename = url.fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function run(elmModulePath, options) {
  const resolved = await resolveInputPathOrModuleName(elmModulePath);
  const { moduleName, projectDirectory, sourceDirectory } = resolved;
  const usesDb = await scriptUsesPagesDb({
    projectDirectory,
    sourceDirectory,
    entryModuleName: moduleName,
  });
  await compileElmForScript(elmModulePath, resolved, { usesDb });

  const cwd = process.cwd();
  process.chdir(projectDirectory);

  if (options.optimize !== undefined && options.debug) {
    console.error(
      "error: The --debug and --optimize options are mutually exclusive."
    );
    process.exit(1);
  }
  if (options.optimize === undefined) {
    options.optimize = "2";
  }
  if (!["0", "1", "2"].includes(options.optimize)) {
    console.error(
      `error: argument ${options.optimize} for the --optimize option is invalid. Allowed choices are 0, 1, 2.`
    );
    process.exit(1);
  }

  const elmEntrypointPath = path.join(
    projectDirectory,
    "elm-stuff/elm-pages/.elm-pages/ScriptMain.elm"
  );
  const elmOutputPath = path.join(
    projectDirectory,
    "elm-stuff/elm-pages/elm.js"
  );
  await compileCliApp(
    { debug: options.debug, optimize: options.optimize },
    elmEntrypointPath,
    elmOutputPath,
    path.join(projectDirectory, "elm-stuff/elm-pages"),
    elmOutputPath
  );
  fs.renameSync(
    `${projectDirectory}/elm-stuff/elm-pages/elm.js`,
    `${projectDirectory}/elm-stuff/elm-pages/elm.cjs`
  );
  process.chdir(cwd);

  try {
    const shouldMinifyBundle = !options.debug && options.optimize !== "0";

    // moduleName, projectDirectory, sourceDirectory already resolved above

    const portBackendTaskFileFound =
      globby.globbySync(path.resolve(projectDirectory, "custom-backend-task.*"))
        .length > 0;

    // Pre-compile custom-backend-task so `BackendTask.Parallel.*` worker
    // pools can import it at runtime. Without this step the worker pool
    // starts but workers can't load the project's ports; parallel-worker
    // requests then return the wrong response shape and Elm surfaces an
    // "Unexpected response body type for internal bytes request" error.
    // Mirrors the pre-compile path in commands/run.js.
    let compiledPortsPath = null;
    if (portBackendTaskFileFound) {
      const portsCheck = await needsPortsRecompilation(projectDirectory);
      compiledPortsPath = portsCheck.outputPath;
      if (portsCheck.needed) {
        await esbuild.build({
          entryPoints: [path.resolve(projectDirectory, "./custom-backend-task")],
          platform: "node",
          outfile: compiledPortsPath,
          assetNames: "[name]-[hash]",
          chunkNames: "chunks/[name]-[hash]",
          metafile: true,
          bundle: true,
          format: "esm",
          packages: "external",
          logLevel: "silent",
        });
      }
    }

    // `parallel-worker.js` is loaded by `new Worker(…)` inside the worker
    // pool, i.e. as a separate file on disk rather than an ESM import. When
    // bundle-script bundles the script runner into one .mjs, the pool's
    // default `path.join(__dirname, "parallel-worker.js")` resolves to the
    // bundled-output directory — which does NOT contain parallel-worker.js.
    // Emit a bundled sibling next to the output and override the pool's
    // `workerEntryPath` at configure time.
    const outputDir = path.dirname(path.resolve(cwd, options.output));
    const bundledWorkerEntryPath = path.join(
      outputDir,
      ".elm-pages-parallel-worker.mjs"
    );
    // `minipass-fetch` and a few other transitively-imported cjs
    // packages use `require("url")` at load time; when esbuild emits
    // ESM, those calls need a `globalThis.require` shim (same trick
    // the main bundle uses). Without this, workers crash on startup
    // with `Dynamic require of "url" is not supported`.
    const WORKER_ESM_REQUIRE_SHIM = `await(async()=>{let{dirname:e}=await import("path"),{fileURLToPath:i}=await import("url");if(typeof globalThis.__filename>"u"&&(globalThis.__filename=i(import.meta.url)),typeof globalThis.__dirname>"u"&&(globalThis.__dirname=e(globalThis.__filename)),typeof globalThis.require>"u"){let{default:a}=await import("module");globalThis.require=a.createRequire(import.meta.url)}})();`;

    await esbuild.build({
      entryPoints: [path.resolve(__dirname, "../parallel-worker.js")],
      platform: "node",
      target: "node18",
      format: "esm",
      bundle: true,
      outfile: bundledWorkerEntryPath,
      external: [
        "node:*",
        // `elm-optimize-level-2` pulls in TypeScript (~8 MB) for its
        // AST passes — used by `compile-elm.js` at build time. Workers
        // never compile Elm; this is dead weight that 4-10× the worker
        // bundle size and adds ~1 s of parse time per worker spawn.
        // Externalize so workers don't carry it; if some future code
        // path on the worker side accidentally imports it, the failure
        // is loud (MODULE_NOT_FOUND) rather than silent bloat.
        "elm-optimize-level-2",
      ],
      // Other node_modules deps stay bundled (cross-spawn, globby, etc.)
      // because they're invoked from generator/src/* code paths a worker
      // genuinely needs at runtime — file IO, port resolution, glob.
      banner: { js: WORKER_ESM_REQUIRE_SHIM },
      logLevel: "silent",
    });

    // Note: resolveDir points to parent directory since we moved to commands/
    const scriptRunner = `${
      portBackendTaskFileFound
        ? `import * as customBackendTask from "${path.resolve(
            projectDirectory,
            "./custom-backend-task"
          )}";`
        : "const customBackendTask = {};"
    }
import * as renderer from "../render.js";
import * as parallelWorkerPool from "../parallel-worker-pool.js";
import { default as Elm } from "${path.join(
      projectDirectory,
      "elm-stuff/elm-pages/elm.cjs"
    )}";

const cliOptions = globalThis.__elmPagesCliOptions || [...process.argv].splice(2);
const isIntrospectionRun = globalThis.__elmPagesIsIntrospectionRun === true;

if (globalThis.__elmPagesOriginalConsoleLog) {
  console.log = globalThis.__elmPagesOriginalConsoleLog;
}

// Mirrors the configure call in commands/run.js — without this,
// BackendTask.Parallel.worker requests route through but workers
// can't locate the project's custom-backend-task, so their responses
// arrive with the wrong body shape. workerEntryPath additionally
// overrides the default sibling-file resolution in parallel-worker-pool
// with the bundled copy of parallel-worker.js emitted next to the
// bundle output.
parallelWorkerPool.configure({
  portsPath: ${compiledPortsPath ? JSON.stringify(compiledPortsPath) : "null"},
  projectDirectory: ${JSON.stringify(projectDirectory)},
  workerEntryPath: ${JSON.stringify(bundledWorkerEntryPath)},
});

await renderer.runGenerator(
  cliOptions,
  customBackendTask,
  Elm,
  "${moduleName}",
  "${options.setVersion || "Version not set."}",
  { suppressConsoleLogDuringInit: isIntrospectionRun }
);
    `;
    // source: https://github.com/evanw/esbuild/pull/2067#issuecomment-1073039746
    const ESM_REQUIRE_SHIM = `
await(async()=>{let{dirname:e}=await import("path"),{fileURLToPath:i}=await import("url");if(typeof globalThis.__filename>"u"&&(globalThis.__filename=i(import.meta.url)),typeof globalThis.__dirname>"u"&&(globalThis.__dirname=e(globalThis.__filename)),typeof globalThis.require>"u"){let{default:a}=await import("module");globalThis.require=a.createRequire(import.meta.url)}})();
`;
    const INTROSPECTION_LOG_SUPPRESSION = `
globalThis.__elmPagesCliOptions = [...process.argv].splice(2);
globalThis.__elmPagesIsIntrospectionRun = (() => {
  for (const cliOption of globalThis.__elmPagesCliOptions) {
    if (cliOption === "--") {
      return false;
    }

    if (cliOption === "--introspect-cli") {
      return true;
    }
  }

  return false;
})();

if (globalThis.__elmPagesIsIntrospectionRun) {
  globalThis.__elmPagesOriginalConsoleLog = console.log;
  console.log = function () {};
}
`;

    await esbuild.build({
      format: "esm",
      platform: "node",
      target: "node18",
      stdin: { contents: scriptRunner, resolveDir: __dirname },
      bundle: true,
      outfile: path.resolve(cwd, options.output),
      external: ["node:*", ...options.external],
      minify: shouldMinifyBundle,
      legalComments: "none",
      drop: shouldMinifyBundle ? ["debugger"] : [],
      charset: "utf8",
      pure: shouldMinifyBundle
        ? [
            "A2",
            "A3",
            "A4",
            "A5",
            "A6",
            "A7",
            "A8",
            "A9",
            "F2",
            "F3",
            "F4",
            "F5",
            "F6",
            "F7",
            "F8",
            "F9",
          ]
        : [],
      absWorkingDir: projectDirectory,
      banner: {
        js: `#!/usr/bin/env node\n\n${ESM_REQUIRE_SHIM}\n${INTROSPECTION_LOG_SUPPRESSION}`,
      },
    });
    // await runTerser(path.resolve(cwd, options.output));
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}
