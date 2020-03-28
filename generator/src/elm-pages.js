#!/usr/bin/env node

const { Elm } = require("./Main.js");
const { version } = require("../../package.json");
const fs = require("fs");
const globby = require("globby");
const develop = require("./develop.js");
const chokidar = require("chokidar");
const doCliStuff = require("./generate-elm-stuff.js");
const { elmPagesUiFile } = require("./elm-file-constants.js");
const generateRecords = require("./generate-records.js");
const parseFrontmatter = require("./frontmatter.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require('./file-helpers.js')
global.builtAt = new Date();

const contentGlobPath = "content/**/*.emu";

let watcher = null;
let devServerRunning = false;

function unpackFile(path) {
  return { path, contents: fs.readFileSync(path).toString() };
}

function unpackMarkup(path) {
  const separated = parseFrontmatter(path, fs.readFileSync(path).toString());
  return {
    path,
    metadata: separated.matter,
    body: separated.content,
    extension: "emu"
  };
}

function parseMarkdown(path, fileContents) {
  const { content, data } = parseFrontmatter(path, fileContents);
  return {
    path,
    metadata: JSON.stringify(data),
    body: content,
    extension: "md"
  };
}

function run() {
  console.log("Running elm-pages...");
  const content = globby.sync([contentGlobPath], {}).map(unpackMarkup);
  const staticRoutes = generateRecords();

  const markdownContent = globby
    .sync(["content/**/*.*", "!content/**/*.emu"], {})
    .map(unpackFile)
    .map(({ path, contents }) => {
      return parseMarkdown(path, contents);
    });

  const images = globby
    .sync("images/**/*", {})
    .filter(imagePath => !fs.lstatSync(imagePath).isDirectory());

  let app = Elm.Main.init({
    flags: {
      argv: process.argv,
      versionMessage: version,
      content,
      markdownContent,
      images
    }
  });

  app.ports.printAndExitSuccess.subscribe(message => {
    console.log(message);
    process.exit(0);
  });

  app.ports.printAndExitFailure.subscribe(message => {
    console.log(message);
    process.exit(1);
  });

  app.ports.writeFile.subscribe(contents => {
    const routes = toRoutes(markdownContent.concat(content));

    doCliStuff(
      contents.watch ? "dev" : "prod",
      staticRoutes,
      markdownContent,
      content,
      function(payload) {
        if (contents.watch) {
          startWatchIfNeeded();
          if (!devServerRunning) {
            devServerRunning = true;
            develop.start({
              routes,
              debug: contents.debug,
              manifestConfig: payload.manifest,
              routesWithRequests: payload.pages,
              filesToGenerate: payload.filesToGenerate,
              customPort: contents.customPort
            });
          }
        } else {
          if (payload.errors && payload.errors.length > 0) {
            printErrorsAndExit(payload.errors);
          }

          develop.run(
            {
              routes,
              manifestConfig: payload.manifest,
              routesWithRequests: payload.pages,
              filesToGenerate: payload.filesToGenerate
            },
            () => {}
          );
        }

        ensureDirSync("./gen");

        // prevent compilation errors if migrating from previous elm-pages version
        deleteIfExists("./gen/Pages/ContentCache.elm");
        deleteIfExists("./gen/Pages/Platform.elm");

        fs.writeFileSync(
          "./gen/Pages.elm",
          elmPagesUiFile(staticRoutes, markdownContent, content)
        );
        console.log("elm-pages DONE");

      }
    );
  });
}

run();

function printErrorsAndExit(errors) {
  console.error(
    "Found errors. Exiting. Fix your content or parsers and re-run, or run in dev mode with `elm-pages develop`."
  );
  console.error(errors.join("\n\n"));
  process.exit(1);
}

function startWatchIfNeeded() {
  if (!watcher) {
    console.log("Watching...");
    watcher = chokidar
      .watch(["content/**/*.*"], {
        awaitWriteFinish: {
          stabilityThreshold: 500
        },
        ignoreInitial: true
      })
      .on("all", function(event, filePath) {
        console.log(`Rerunning for ${filePath}...`);
        run();
        console.log("Done!");
      });
  }
}

function toRoutes(entries) {
  return entries.map(toRoute);
}

function toRoute(entry) {
  let fullPath = entry.path
    .replace(/(index)?\.[^/.]+$/, "")
    .split("/")
    .filter(item => item !== "")
    .slice(1);

  return fullPath.join("/");
}
