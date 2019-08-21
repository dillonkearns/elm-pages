#!/usr/bin/env node

const { Elm } = require("./Main.js");
const { version } = require("../../package.json");
const fs = require("fs");
const glob = require("glob");
const develop = require("./develop.js");
const chokidar = require("chokidar");
const matter = require("gray-matter");
const runElm = require("./compile-elm.js");
const doCliStuff = require("./generate-elm-stuff.js");
const { elmPagesUiFile } = require("./elm-file-constants.js");
const generateRecords = require("./generate-records.js");
const generateRawContent = require("./generate-raw-content.js");

const contentGlobPath = "content/**/*.emu";

let watcher = null;
let devServerRunning = false;

function unpackFile(path) {
  return { path, contents: fs.readFileSync(path).toString() };
}

const markupFrontmatterOptions = {
  language: "markup",
  engines: {
    markup: {
      parse: function(string) {
        console.log("@@@@@@", string);
        return string;
      },

      // example of throwing an error to let users know stringifying is
      // not supported (a TOML stringifier might exist, this is just an example)
      stringify: function(string) {
        return string;
      }
    }
  }
};

function unpackMarkup(path) {
  console.log("!!! 2");
  const separated = matter(
    fs.readFileSync(path).toString(),
    markupFrontmatterOptions
  );
  return { path, metadata: separated.matter, body: separated.content };
}

function parseMarkdown(path, fileContents) {
  console.log("!!! 3");
  const { content, data } = matter(fileContents, markupFrontmatterOptions);
  return { path, metadata: JSON.stringify(data), body: content };
}

function run() {
  console.log("Running elm-pages...");
  const content = glob.sync(contentGlobPath, {}).map(unpackMarkup);
  const staticRoutes = generateRecords();

  const markdownContent = glob
    .sync("content/**/*.md", {})
    .map(unpackFile)
    .map(({ path, contents }) => {
      return parseMarkdown(path, contents);
    });
  const images = glob
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
    const rawContent = generateRawContent(markdownContent, content);

    fs.writeFileSync("./gen/RawContent.elm", rawContent);
    fs.writeFileSync("./gen/PagesNew.elm", elmPagesUiFile(staticRoutes));
    console.log("elm-pages DONE");
    doCliStuff(staticRoutes, rawContent, function(manifestConfig) {
      if (contents.watch) {
        startWatchIfNeeded();
        if (!devServerRunning) {
          devServerRunning = true;
          develop.start({
            routes: contents.routes,
            debug: contents.debug,
            manifestConfig
          });
        }
      } else {
        develop.run(
          {
            routes: contents.routes,
            manifestConfig
          },
          () => {}
        );
      }
    });
  });
}

run();

function startWatchIfNeeded() {
  if (!watcher) {
    console.log("Watching...");
    watcher = chokidar
      .watch([contentGlobPath, "content/**/*.md"], {
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
