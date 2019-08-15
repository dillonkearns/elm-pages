#!/usr/bin/env node

const { Elm } = require("./Main.js");
const { version } = require("../../package.json");
const fs = require("fs");
const glob = require("glob");
const develop = require("./develop.js");
const chokidar = require("chokidar");
const { buildSW } = require("./build-service-worker.js");
const matter = require("gray-matter");

const contentGlobPath = "content/**/*.emu";

let watcher = null;

function unpackFile(path) {
  return { path, contents: fs.readFileSync(path).toString() };
}

function parseMarkdown(path, fileContents) {
  const { content, data } = matter(fileContents);
  return { path, metadata: JSON.stringify(data), body: content };
}

function run() {
  console.log("Running elm-pages...");
  const content = glob.sync(contentGlobPath, {}).map(unpackFile);
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
    fs.writeFileSync("./gen/RawContent.elm", contents.rawContent);
    fs.writeFileSync("./src/js/image-assets.js", contents.imageAssets);
    console.log("elm-pages DONE");
    if (contents.watch) {
      startWatchIfNeeded();
      develop.start({ routes: contents.routes });
    } else {
      develop.run({ routes: contents.routes }, () => {
        buildSW();
      });
    }
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
