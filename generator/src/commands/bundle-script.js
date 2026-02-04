/**
 * Bundle-script command - bundles an elm-pages script for distribution.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";
import * as esbuild from "esbuild";
import * as globby from "globby";
import * as build from "../build.js";
import { resolveInputPathOrModuleName } from "../resolve-elm-module.js";
import { restoreColorSafe } from "../error-formatter.js";
import {
  compileElmForScript,
  lamderaOrElmFallback,
  printCaughtError,
} from "./shared.js";

const __filename = url.fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function run(elmModulePath, options) {
  const resolved = await resolveInputPathOrModuleName(elmModulePath);
  const { moduleName, projectDirectory, sourceDirectory } = resolved;
  await compileElmForScript(elmModulePath, resolved);

  const cwd = process.cwd();
  process.chdir(projectDirectory);
  // TODO have option for compiling with --debug or not (maybe allow running with elm-optimize-level-2 as well?)

  let executableName = await lamderaOrElmFallback();
  await build.compileCliApp({
    debug: options.debug,
    executableName,
    mainModule: "ScriptMain",
    isScript: true,
  });
  // await runTerser(`${projectDirectory}/elm-stuff/elm-pages/elm.js`);
  fs.renameSync(
    `${projectDirectory}/elm-stuff/elm-pages/elm.js`,
    `${projectDirectory}/elm-stuff/elm-pages/elm.cjs`
  );
  process.chdir(cwd);

  try {
    // moduleName, projectDirectory, sourceDirectory already resolved above

    const portBackendTaskFileFound =
      globby.globbySync(
        path.resolve(projectDirectory, "custom-backend-task.*")
      ).length > 0;

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

await renderer.runGenerator(
  [...process.argv].splice(2),
  customBackendTask,
  Elm,
  "${moduleName}",
  "${options.setVersion || "Version not set."}"
);
    `;
    // source: https://github.com/evanw/esbuild/pull/2067#issuecomment-1073039746
    const ESM_REQUIRE_SHIM = `
await(async()=>{let{dirname:e}=await import("path"),{fileURLToPath:i}=await import("url");if(typeof globalThis.__filename>"u"&&(globalThis.__filename=i(import.meta.url)),typeof globalThis.__dirname>"u"&&(globalThis.__dirname=e(globalThis.__filename)),typeof globalThis.require>"u"){let{default:a}=await import("module");globalThis.require=a.createRequire(import.meta.url)}})();
`;

    await esbuild.build({
      format: "esm",
      platform: "node",
      stdin: { contents: scriptRunner, resolveDir: __dirname },
      bundle: true,
      // TODO do I need to make the outfile joined with the current working directory?

      outfile: path.resolve(cwd, options.output),
      external: ["node:*", ...options.external],
      minify: true,
      pure: [
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
        "F3",
        "F4",
        "F5",
        "F6",
        "F7",
        "F8",
        "F9",
      ],
      absWorkingDir: projectDirectory,
      banner: { js: `#!/usr/bin/env node\n\n${ESM_REQUIRE_SHIM}` },
    });
    // await runTerser(path.resolve(cwd, options.output));
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}
