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

    doCliStuff(staticRoutes, markdownContent, content, function(payload) {
      if (contents.watch) {
        startWatchIfNeeded();
        if (!devServerRunning) {
          devServerRunning = true;
          develop.start({
            routes,
            debug: contents.debug,
            customPort: contents.customPort,
            manifestConfig: payload.manifest
          });
        }
      } else {
        if (payload.errors) {
          printErrorsAndExit(payload.errors);
        }

        develop.run(
          {
            routes,
            manifestConfig: payload.manifest
          },
          () => {}
        );
      }

      ensureDirSync("./gen");
      fs.writeFileSync(
          "./gen/Pages.elm",
          elmPagesUiFile(staticRoutes, markdownContent, content)
      );
      ensureDirSync("./gen/Pages");
      fs.copyFileSync(
          path.resolve(__dirname, "../../elm-package/src/Pages/ContentCache.elm"),
          "./gen/Pages/ContentCache.elm"
      );
      fs.copyFileSync(
          path.resolve(__dirname, "../../elm-package/src/Pages/Platform.elm"),
          "./gen/Pages/Platform.elm"
      );
      console.log("elm-pages DONE");
    });
  });
}

run();

function printErrorsAndExit(errors) {
  console.error(
    "Found errors. Exiting. Fix your content or parsers and re-run, or run in dev mode with `elm-pages develop`."
  );
  console.error(errors);
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
    .filter(item => item !== "");
  fullPath.splice(0, 1);
  return `/${fullPath.join("/")}`;
}

function ensureDirSync(dirpath) {
  try {
    fs.mkdirSync(dirpath, { recursive: true });
  } catch (err) {
    if (err.code !== "EEXIST") throw err;
  }
}
