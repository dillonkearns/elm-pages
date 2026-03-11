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
import { default as Elm } from "${path.join(
      projectDirectory,
      "elm-stuff/elm-pages/elm.cjs"
    )}";

const cliOptions = globalThis.__elmPagesCliOptions || [...process.argv].splice(2);
const isIntrospectionRun = globalThis.__elmPagesIsIntrospectionRun === true;

if (globalThis.__elmPagesOriginalConsoleLog) {
  console.log = globalThis.__elmPagesOriginalConsoleLog;
}

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

    if (cliOption === "--introspect") {
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
