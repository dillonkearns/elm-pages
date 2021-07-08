#!/usr/bin/env node

const build = require("./build.js");
const dev = require("./dev-server.js");
const generate = require("./codegen-template-module.js");
const init = require("./init.js");
const codegen = require("./codegen.js");

const commander = require("commander");

const packageVersion = require("../../package.json").version;

async function main() {
  const program = new commander.Command();

  program.version(packageVersion);

  program
    .command("build")
    .option("--debug", "Skip terser and run elm make with --debug")
    .description("run a full site build")
    .action(async (options) => {
      await build.run(options);
    });

  program
    .command("dev")
    .description("start a dev server")
    .option("--port <number>", "serve site at localhost:<port>", "1234")
    .action(async (options) => {
      console.log({ options });
      await dev.start(options);
    });

  program
    .command("add <moduleName>")
    .description("create a new Page module")
    .action(async (moduleName) => {
      await generate.run({ moduleName });
    });

  program
    .command("init <projectName>")
    .description("scaffold a new elm-pages project boilerplate")
    .action(async (projectName) => {
      await init.run(projectName);
    });

  program
    .command("docs")
    .description("open the docs for locally generated modules")
    .option("--port <number>", "serve site at localhost:<port>", "8000")
    .action(async (options) => {
      await codegen.generate();
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

main();
