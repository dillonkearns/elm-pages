#!/usr/bin/env node

const build = require("./build.js");
const dirHelpers = require("./dir-helpers.js");
const dev = require("./dev-server.js");
const generate = require("./codegen-template-module.js");
const init = require("./init.js");
const codegen = require("./codegen.js");
const fs = require("fs");
const path = require("path");

const commander = require("commander");
const { compileCliApp } = require("./compile-elm.js");
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
    .command("add <moduleName>")
    .addOption(
      new Option("--state <state>", "Generate Page Module with state").choices([
        "local",
        "shared",
      ])
    )
    .option("--server-render", "Generate a Page.serverRender Page Module")
    .option(
      "--with-fallback",
      "Generate a Page.preRenderWithFallback Page Module"
    )
    .description("create a new Page module")
    .action(async (moduleName, options, b, c) => {
      await generate.run({
        moduleName,
        withState: options.state,
        serverRender: options.serverRender,
        withFallback: options.withFallback,
      });
    });

  program
    .command("init <projectName>")
    .description("scaffold a new elm-pages project boilerplate")
    .action(async (projectName) => {
      await init.run(projectName);
    });

  program
    .command("codegen <moduleName>")
    .description("run a generator")
    .allowUnknownOption()
    .allowExcessArguments()
    .action(async (moduleName, options, options2) => {
      if (!/^[A-Z][a-zA-Z0-9_]*(\.[A-Z][a-zA-Z0-9_]*)*$/.test(moduleName)) {
        throw `Invalid module name "${moduleName}", must be in the format of an Elm module`;
      }
      const splitModuleName = moduleName.split(".");
      const expectedFilePath = path.join(
        process.cwd(),
        "codegen",
        `${splitModuleName.join("/")}.elm`
      );
      if (!fs.existsSync(expectedFilePath)) {
        throw `I couldn't find a module named ${expectedFilePath}`;
      }
      // const DocServer = require("elm-doc-preview");
      // const elmDocPreviewServer = new DocServer({
      //   browser: false,
      //   dir: ".",
      // });
      // elmDocPreviewServer.make("docs.json");
      // elm make Cli.elm --optimize --output elm.js
      await compileCliApp(
        // { debug: true },
        {},
        `${splitModuleName.join("/")}.elm`,
        path.join(process.cwd(), "codegen/elm-stuff/scaffold.js"),
        // "elm-stuff/scaffold.js",
        "codegen",

        path.join(process.cwd(), "codegen/elm-stuff/scaffold.js")
        // "elm-stuff/scaffold.js"
      );

      const elmScaffoldProgram = getAt(
        splitModuleName,
        require(path.join(process.cwd(), "./codegen/elm-stuff/scaffold.js")).Elm
      );
      const program = elmScaffoldProgram.init({
        flags: { argv: ["", ...options2.args], versionMessage: "1.2.3" },
      });

      safeSubscribe(program, "print", (message) => {
        console.log(message);
      });
      safeSubscribe(program, "printAndExitFailure", (message) => {
        console.log(message);
        process.exit(1);
      });
      safeSubscribe(program, "printAndExitSuccess", (message) => {
        console.log(message);
        process.exit(0);
      });
      safeSubscribe(program, "writeFile", async (info) => {
        const filePath = path.join(process.cwd(), "app", info.path);
        await dirHelpers.tryMkdir(path.dirname(filePath));
        fs.writeFileSync(filePath, info.body);
        console.log("Success! Created file", filePath);
        process.exit(0);
      });
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

main();
