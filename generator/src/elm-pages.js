#!/usr/bin/env node

const { Elm } = require("./Main.js");
const { version } = require("../../package.json");
const fs = require("fs");
const globby = require("globby");
const develop = require("./develop.js");
const parseFrontmatter = require("./frontmatter.js");
const generateRecords = require("./generate-records.js");
const doCliStuff = require("./generate-elm-stuff.js");
global.builtAt = new Date();
global.staticHttpCache = {};

function unpackFile(path) {
  return { path, contents: fs.readFileSync(path).toString() };
}


function parseMarkdown(path, fileContents) {
  const { content, data } = parseFrontmatter(path, fileContents);
  return {
    path,
    metadata: JSON.stringify(data),
    body: content
  };
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

  app.ports.writeFile.subscribe(cliOptions => {


    const markdownContent = globby
      .sync(["content/**/*.*"], {})
      .map(unpackFile)
      .map(({ path, contents }) => {
        return parseMarkdown(path, contents);
      });
    const routes = toRoutes(markdownContent);

    global.mode = cliOptions.watch ? "dev" : "prod"
    generateRecords().then((staticRoutes) =>
      doCliStuff(
        global.mode,
        staticRoutes,
        markdownContent
      )
    ).then((payload) => {
      if (cliOptions.watch) {
        develop.start({
          routes,
          debug: cliOptions.debug,
          customPort: cliOptions.customPort,
          manifestConfig: payload.manifest,

        });
      } else {
        develop.run({
          routes,
          debug: cliOptions.debug,
          customPort: cliOptions.customPort,
          manifestConfig: payload.manifest,
        });
      }

    }).catch(function (errorPayload) {
      if (cliOptions.watch) {
        develop.start({
          routes,
          debug: cliOptions.debug,
          customPort: cliOptions.customPort,
          manifestConfig: stubManifest,

        });
      } else {
        console.error(errorPayload)
        process.exit(1)
      }
    })




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
