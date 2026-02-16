#!/usr/bin/env node
"use strict";

/**
 * elm-pages CLI
 *
 * Commands are lazy-loaded from the commands/ directory to minimize startup time.
 * This allows `elm-pages --help` to be instant (~40ms) while only loading
 * heavy dependencies when actually running a command.
 */

import * as commander from "commander";
import { packageVersion } from "./compatibility-key.js";

function collect(value, previous) {
  return previous.concat([value]);
}

async function main() {
  const program = new commander.Command();

  // Make Commander exit with proper exit code on errors
  program.exitOverride((err) => {
    if (err.exitCode !== 0) {
      process.exitCode = err.exitCode;
    }
    throw err;
  });

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
    .option(
      "--strict",
      "Fail the build if View.freeze is used incorrectly (wrong module scope or de-optimized due to model usage)"
    )
    .description("run a full site build")
    .action(async (options) => {
      const { run } = await import("./commands/build.js");
      await run(options);
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
      const { run } = await import("./commands/gen.js");
      await run(options);
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
      const { run } = await import("./commands/dev.js");
      await run(options);
    });

  program
    .command("init <projectName>")
    .description("scaffold a new elm-pages project boilerplate")
    .action(async (projectName) => {
      const { run } = await import("./commands/init.js");
      await run(projectName);
    });

  program
    .command("run <elmModulePath>")
    .description("run an elm-pages script")
    .allowUnknownOption()
    .allowExcessArguments()
    .helpOption(false) // allow --help to propagate to the Script to show usage
    .action(async (elmModulePath, options, options2) => {
      const { run } = await import("./commands/run.js");
      await run(elmModulePath, options, options2);
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
      "--set-version <version>",
      "Set the version string for the bundled script"
    )
    .option(
      "--external <package-or-pattern>",
      "Mark packages as external in the bundle",
      collect,
      []
    )
    .action(async (elmModulePath, options) => {
      const { run } = await import("./commands/bundle-script.js");
      await run(elmModulePath, options);
    });

  program
    .command("docs")
    .description("open the docs for locally generated modules")
    .option("--port <number>", "serve site at localhost:<port>", "8000")
    .action(async (options) => {
      const { run } = await import("./commands/docs.js");
      await run(options);
    });

  program.parse(process.argv);
}

// Ensure proper exit code on unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled rejection:', reason);
  process.exit(1);
});

main().catch((err) => {
  process.exit(1);
});
