#!/usr/bin/env node

const build = require("./build.js");
const dev = require("./dev-server.js");
const generate = require("./codegen-template-module.js");

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

  program.parse(process.argv);
}

main();
