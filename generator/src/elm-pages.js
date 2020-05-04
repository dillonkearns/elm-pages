#!/usr/bin/env node

const { Elm } = require("./Main.js");
const { version } = require("../../package.json");
const fs = require("fs");
const globby = require("globby");
const develop = require("./develop.js");
const parseFrontmatter = require("./frontmatter.js");
global.builtAt = new Date();
global.staticHttpCache = {};

function unpackFile(path) {
  return { path, contents: fs.readFileSync(path).toString() };
}

const stubManifest = {
  sourceIcon: 'images/icon-png.png',
  background_color: '#ffffff',
  orientation: 'portrait',
  display: 'standalone',
  categories: ['education'],
  description: 'elm-pages - A statically typed site generator.',
  name: 'elm-pages docs',
  prefer_related_applications: false,
  related_applications: [],
  theme_color: '#ffffff',
  start_url: '',
  short_name: 'elm-pages',
  serviceworker: {
    src: '../service-worker.js',
    scope: '/',
    type: '',
    update_via_cache: 'none'
  }
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
  const markdownContent = globby
    .sync(["content/**/*.*"], {})
    .map(unpackFile)
    .map(({ path, contents }) => {
      return parseMarkdown(path, contents);
    });

  let app = Elm.Main.init({
    flags: {
      argv: process.argv,
      versionMessage: version,
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
    const routes = toRoutes(markdownContent);

    global.mode = contents.watch ? "dev" : "prod"

    if (contents.watch) {
      develop.start({
        routes,
        debug: contents.debug,
        manifestConfig: stubManifest,
        routesWithRequests: {},
        filesToGenerate: [],
        customPort: contents.customPort
      });
    } else {
      develop.run({
        routes,
        debug: contents.debug,
        manifestConfig: stubManifest,
        routesWithRequests: {},
        filesToGenerate: [],
        customPort: contents.customPort
      });
    }

  });
}

run();

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
