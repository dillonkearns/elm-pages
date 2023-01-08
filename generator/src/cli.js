#!/usr/bin/env node

const build = require("./build.js");
const dirHelpers = require("./dir-helpers.js");
const dev = require("./dev-server.js");
const init = require("./init.js");
const codegen = require("./codegen.js");
const fs = require("fs");
const path = require("path");
const { restoreColorSafe } = require("./error-formatter");
const renderer = require("../../generator/src/render");
const globby = require("globby");
const esbuild = require("esbuild");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { ensureDirSync, deleteIfExists } = require("./file-helpers.js");

const commander = require("commander");
const { runElmCodegenInstall } = require("./elm-codegen.js");
const Argument = commander.Argument;
const Option = commander.Option;

const packageVersion = require("../../package.json").version;

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
      if (!options.keepCache) {
        clearHttpAndPortCache();
      }
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
      if (!options.keepCache) {
        clearHttpAndPortCache();
      }
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
        await copyModifiedElmJson(
          "./script/elm.json",
          "./script/elm-stuff/elm-pages/elm.json"
        );

        const portBackendTaskCompiled = esbuild
          .build({
            entryPoints: ["./port-data-source"],
            platform: "node",
            outfile: ".elm-pages/compiled-ports/port-data-source.js",
            assetNames: "[name]-[hash]",
            chunkNames: "chunks/[name]-[hash]",
            outExtension: { ".js": ".js" },
            metafile: true,
            bundle: true,
            watch: false,
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
              globby.sync("./port-data-source.*").length > 0;
            if (portBackendTaskFileFound) {
              // don't present error if there are no files matching port-data-source
              // if there are files matching port-data-source, warn the user in case something went wrong loading it
              console.error("Failed to start port-data-source watcher", error);
            }
          });
        const portsPath = await portBackendTaskCompiled;
        const resolvedPortsPath =
          portsPath && path.join(process.cwd(), portsPath);

        process.chdir("./script");
        // TODO have option for compiling with --debug or not (maybe allow running with elm-optimize-level-2 as well?)
        await build.compileCliApp({ debug: "debug" });
        process.chdir("../");
        await renderer.runGenerator(
          unprocessedCliOptions,
          resolvedPortsPath,
          requireElm("./script/elm-stuff/elm-pages/elm.js")
        );
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
      const DocServer = require("elm-doc-preview");
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

function clearHttpAndPortCache() {
  const directory = ".elm-pages/http-response-cache";
  if (fs.existsSync(directory)) {
    fs.readdir(directory, (err, files) => {
      if (err) {
        throw err;
      }

      for (const file of files) {
        fs.unlink(path.join(directory, file), (err) => {
          if (err) {
            throw err;
          }
        });
      }
    });
  }
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
function requireElm(compiledElmPath) {
  const warnOriginal = console.warn;
  console.warn = function () {};

  Elm = require(path.resolve(compiledElmPath));
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
import Exception
import Cli.Program as Program
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.Platform.GeneratorApplication
import ${moduleName}


main : Program.StatefulProgram Pages.Internal.Platform.GeneratorApplication.Model Pages.Internal.Platform.GeneratorApplication.Msg (BackendTask Exception.Throwable ()) Pages.Internal.Platform.GeneratorApplication.Flags
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

main();
