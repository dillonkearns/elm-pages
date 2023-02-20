#!/usr/bin/env node
"use strict";

import * as build from "./build.js";
import * as dev from "./dev-server.js";
import * as init from "./init.js";
import * as codegen from "./codegen.js";
import * as fs from "node:fs";
import * as path from "node:path";
import { restoreColorSafe } from "./error-formatter.js";
import * as renderer from "./render.js";
import * as globby from "globby";
import * as esbuild from "esbuild";
import { rewriteElmJson } from "./rewrite-elm-json.js";
import { ensureDirSync } from "./file-helpers.js";
import * as url from "url";

import * as commander from "commander";
import { runElmCodegenInstall } from "./elm-codegen.js";
import { packageVersion } from "./compatibility-key.js";

const Argument = commander.Argument;
const Option = commander.Option;
const __filename = url.fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const program = new commander.Command();

  program.version(packageVersion);

  program
    .command("build")
    .option("--debug", "Skip terser and run elm make with --debug")
    .option(
      "--base <basePath>",
      "build site to be served under a base path",
      "/"
    )
    .option(
      "--keep-cache",
      "Preserve the HTTP and JS Port cache instead of deleting it on server start"
    )
    .description("run a full site build")
    .action(async (options) => {
      options.base = normalizeUrl(options.base);
      await build.run(options);
    });

  program
    .command("gen")
    .option(
      "--base <basePath>",
      "build site to be served under a base path",
      "/"
    )
    .description(
      "generate code, useful for CI where you don't want to run a full build"
    )
    .action(async (options) => {
      await codegen.generate(options.base);
    });

  program
    .command("dev")
    .description("start a dev server")
    .option("--port <number>", "serve site at localhost:<port>", "1234")
    .option("--debug", "Run elm make with --debug")
    .option(
      "--keep-cache",
      "Preserve the HTTP and JS Port cache instead of deleting it on server start"
    )
    .option("--base <basePath>", "serve site under a base path", "/")
    .option("--https", "uses a https server")
    .action(async (options) => {
      options.base = normalizeUrl(options.base);
      await dev.start(options);
    });

  program
    .command("init <projectName>")
    .description("scaffold a new elm-pages project boilerplate")
    .action(async (projectName) => {
      await init.run(projectName);
    });

  program
    .command("run <moduleName>")
    .description("run an elm-pages script")
    .allowUnknownOption()
    .allowExcessArguments()
    .action(async (moduleName, options, options2) => {
      const unprocessedCliOptions = options2.args.splice(
        options2.processedArgs.length,
        options2.args.length
      );
      if (!/^[A-Z][a-zA-Z0-9_]*(\.[A-Z][a-zA-Z0-9_]*)*$/.test(moduleName)) {
        throw `Invalid module name "${moduleName}", must be in the format of an Elm module`;
      }
      const splitModuleName = moduleName.split(".");
      const expectedFilePath = path.join(
        process.cwd(),
        "script/src/",
        `${splitModuleName.join("/")}.elm`
      );
      if (!fs.existsSync(expectedFilePath)) {
        throw `I couldn't find a module named ${expectedFilePath}`;
      }
      try {
        // await codegen.generate("");
        ensureDirSync(
          path.join(process.cwd(), ".elm-pages", "http-response-cache")
        );
        if (fs.existsSync("./codegen/")) {
          await runElmCodegenInstall();
        }

        ensureDirSync("./script/elm-stuff");
        ensureDirSync("./script/elm-stuff/elm-pages/.elm-pages");
        await fs.promises.writeFile(
          path.join("./script/elm-stuff/elm-pages/.elm-pages/Main.elm"),
          generatorWrapperFile(moduleName)
        );
        await rewriteElmJson(
          "./script/elm.json",
          "./script/elm-stuff/elm-pages/elm.json"
        );

        const portBackendTaskCompiled = esbuild
          .build({
            entryPoints: ["./custom-backend-task"],
            platform: "node",
            outfile: ".elm-pages/compiled-ports/custom-backend-task.mjs",
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
              globby.globbySync("./custom-backend-task.*").length > 0;
            if (portBackendTaskFileFound) {
              // don't present error if there are no files matching custom-backend-task
              // if there are files matching custom-backend-task, warn the user in case something went wrong loading it
              console.error(
                "Failed to start custom-backend-task watcher",
                error
              );
            }
          });
        const portsPath = await portBackendTaskCompiled;

        process.chdir("./script");
        // TODO have option for compiling with --debug or not (maybe allow running with elm-optimize-level-2 as well?)
        await build.compileCliApp({ debug: "debug" });
        process.chdir("../");
        fs.renameSync(
          "./script/elm-stuff/elm-pages/elm.js",
          "./script/elm-stuff/elm-pages/elm.cjs"
        );
        await renderer.runGenerator(
          unprocessedCliOptions,
          portsPath
            ? await import(url.pathToFileURL(path.resolve(portsPath)).href)
            : null,
          await requireElm("./script/elm-stuff/elm-pages/elm.cjs"),
          moduleName
        );
      } catch (error) {
        console.log(restoreColorSafe(error));
        process.exit(1);
      }
    });

  program
    .command("bundle-script <moduleName>")
    .description("bundle an elm-pages script")
    .option(
      "--debug",
      "Skip elm-optimize-level-2 and run elm make with --debug"
    )
    .option(
      "--output <path>",
      "Output path for compiled script",
      "./myscript.mjs"
    )
    .option(
      "--external <package-or-pattern>",
      "build site to be served under a base path",
      collect,
      []
    )
    .action(async (moduleName, options, options2) => {
      if (!/^[A-Z][a-zA-Z0-9_]*(\.[A-Z][a-zA-Z0-9_]*)*$/.test(moduleName)) {
        throw `Invalid module name "${moduleName}", must be in the format of an Elm module`;
      }
      const splitModuleName = moduleName.split(".");
      const expectedFilePath = path.join(
        process.cwd(),
        "script/src/",
        `${splitModuleName.join("/")}.elm`
      );
      if (!fs.existsSync(expectedFilePath)) {
        throw `I couldn't find a module named ${expectedFilePath}`;
      }
      try {
        if (fs.existsSync("./codegen/")) {
          await runElmCodegenInstall();
        }

        ensureDirSync("./script/elm-stuff");
        ensureDirSync("./script/elm-stuff/elm-pages/.elm-pages");
        await fs.promises.writeFile(
          path.join("./script/elm-stuff/elm-pages/.elm-pages/Main.elm"),
          generatorWrapperFile(moduleName)
        );
        await rewriteElmJson(
          "./script/elm.json",
          "./script/elm-stuff/elm-pages/elm.json"
        );

        process.chdir("./script");
        // TODO have option for compiling with --debug or not (maybe allow running with elm-optimize-level-2 as well?)
        console.log("Compiling...");
        await build.compileCliApp({ debug: options.debug });
        process.chdir("../");
        if (!options.debug) {
          console.log("Running elm-optimize-level-2...");
          await build.elmOptimizeLevel2(
            "./script/elm-stuff/elm-pages/elm.js",
            process.cwd()
          );
        }
        fs.renameSync(
          "./script/elm-stuff/elm-pages/elm.js",
          "./script/elm-stuff/elm-pages/elm.cjs"
        );
        // TODO allow no custom-backend-task
        const portBackendTaskFileFound =
          globby.globbySync("./custom-backend-task.*").length > 0;

        const scriptRunner = `${
          portBackendTaskFileFound
            ? `import * as customBackendTask from "${path.resolve(
                "./custom-backend-task"
              )}";`
            : "const customBackendTask = {};"
        }
import * as renderer from "./render.js";
import { default as Elm } from "${path.resolve(
          "./script/elm-stuff/elm-pages/elm.cjs"
        )}";

await renderer.runGenerator(
  [...process.argv].splice(2),
  customBackendTask,
  Elm,
  "${moduleName}"
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
          outfile: options.output,
          external: ["node:*", ...options.external],
          minify: true,
          banner: { js: `#!/usr/bin/env node\n\n${ESM_REQUIRE_SHIM}` },
        });
      } catch (error) {
        console.log(restoreColorSafe(error));
        process.exit(1);
      }
    });

  program
    .command("docs")
    .description("open the docs for locally generated modules")
    .option("--port <number>", "serve site at localhost:<port>", "8000")
    .action(async (options) => {
      await codegen.generate("/");
      const DocServer = (await import("elm-doc-preview")).default;
      const server = new DocServer({
        port: options.port,
        browser: true,
        dir: "./elm-stuff/elm-pages/",
      });

      server.listen();
    });

  program.parse(process.argv);
}

/**
 * @param {string[]} properties
 * @param {Object} object
 * @returns unknown
 */
function getAt(properties, object) {
  if (properties.length === 0) {
    return object;
  } else {
    const [next, ...rest] = properties;
    return getAt(rest, object[next]);
  }
}

function safeSubscribe(program, portName, subscribeFunction) {
  program.ports &&
    program.ports[portName] &&
    program.ports[portName].subscribe(subscribeFunction);
}

/**
 * @param {string} rawPagePath
 */
function normalizeUrl(rawPagePath) {
  const segments = rawPagePath
    .split("/")
    // Filter out all empty segments.
    .filter((segment) => segment.length != 0);

  // Do not add a trailing slash.
  // The core issue is that `/base` is a prefix of `/base/`, but
  // `/base/` is not a prefix of `/base`, which can later lead to issues
  // with detecting whether the path contains the base.
  return `/${segments.join("/")}`;
}
/**
 * @param {string} compiledElmPath
 */
async function requireElm(compiledElmPath) {
  const warnOriginal = console.warn;
  console.warn = function () {};

  let Elm = (await import(path.resolve(compiledElmPath))).default;
  console.warn = warnOriginal;
  return Elm;
}

/**
 * @param {string} moduleName
 */
function generatorWrapperFile(moduleName) {
  return `port module Main exposing (main)

import Bytes
import BackendTask exposing (BackendTask)
import FatalError
import Cli.Program as Program
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.Platform.GeneratorApplication
import ${moduleName}


main : Program.StatefulProgram Pages.Internal.Platform.GeneratorApplication.Model Pages.Internal.Platform.GeneratorApplication.Msg (BackendTask FatalError.FatalError ()) Pages.Internal.Platform.GeneratorApplication.Flags
main =
    Pages.Internal.Platform.GeneratorApplication.app
        { data = ${moduleName}.run
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , gotBatchSub = gotBatchSub identity
        , sendPageData = sendPageData
        }


port toJsPort : Encode.Value -> Cmd msg


port fromJsPort : (Decode.Value -> msg) -> Sub msg


port gotBatchSub : (Decode.Value -> msg) -> Sub msg


port sendPageData : { oldThing : Encode.Value, binaryPageData : Bytes.Bytes } -> Cmd msg
`;
}
function collect(value, previous) {
  return previous.concat([value]);
}

main();
