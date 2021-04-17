#!/usr/bin/env node

const build = require("./build.js");

const commander = require("commander");

const packageVersion = require("../../package.json").version;

async function main() {
  const program = new commander.Command();

  program
    .version(packageVersion)
    .command("build")
    .option("--debug", "Skip terser and run elm make with --debug")
    .description("run a full site build")
    .action(async (options) => {
      await build.run(options);
    });

  program.parse(process.argv);
}

main();
