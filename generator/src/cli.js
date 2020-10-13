const fs = require("fs");
const path = require("path");
const seo = require("./seo-renderer.js");
const util = require("util");
const exec = util.promisify(require("child_process").exec);
const codegen = require("./codegen.js");

const DIR_PATH = path.join(process.cwd());
const OUTPUT_FILE_NAME = "elm.js";

const ELM_FILE_PATH = path.join(
  DIR_PATH,
  "./elm-stuff/elm-pages",
  OUTPUT_FILE_NAME
);

async function run() {
  XMLHttpRequest = require("xhr2");

  await codegen.generate();

  await compileCliApp();

  compileElm();

  // const value = await runElmApp();
  // outputString(value);
  runElmApp();
  // console.log("Got value", value);
}

function runElmApp() {
  return new Promise((resolve, _) => {
    const mode /** @type { "dev" | "prod" } */ = "elm-to-html-beta";
    const staticHttpCache = {};
    const app = require(ELM_FILE_PATH).Elm.Main.init({
      flags: { secrets: process.env, mode, staticHttpCache },
    });

    app.ports.toJsPort.subscribe((/** @type { FromElm }  */ fromElm) => {
      // console.log("@@@ fromElm", fromElm);
      // resolve(fromElm);
      outputString(fromElm);
    });
  });
}

/**
 * @param {string} route
 */
function cleanRoute(route) {
  return route.replace(/(^\/|\/$)/, "");
}

/**
 * @param {string} elmPath
 */
function elmToEsm(elmPath) {
  const elmEs3 = fs.readFileSync(elmPath, "utf8");

  const elmEsm =
    "\n" +
    "const scope = {};\n" +
    elmEs3.replace("}(this));", "}(scope));") +
    "export const { Elm } = scope;\n" +
    "\n";

  fs.writeFileSync(elmPath, elmEsm);
}

/**
 * @param {string} cleanedRoute
 */
function pathToRoot(cleanedRoute) {
  return cleanedRoute === ""
    ? cleanedRoute
    : cleanedRoute
        .split("/")
        .map((_) => "..")
        .join("/")
        .replace(/\.$/, "./");
}

/**
 * @param {string} route
 */
function baseRoute(route) {
  const cleanedRoute = cleanRoute(route);
  return cleanedRoute === "" ? "./" : pathToRoot(route);
}

function outputString(/** @type { FromElm } */ fromElm) {
  let contentJson = {};
  contentJson["body"] = "Hello!";
  contentJson["staticData"] = fromElm.contentJson;
  const normalizedRoute = fromElm.route.replace(/index$/, "");
  fs.mkdirSync(`./dist/${normalizedRoute}`, { recursive: true });
  fs.writeFileSync(`dist/${normalizedRoute}/index.html`, wrapHtml(fromElm));
  fs.writeFileSync(
    `dist/${normalizedRoute}/content.json`,
    JSON.stringify(contentJson)
  );
}

async function compileElm() {
  await shellCommand(
    `elm-optimize-level-2 src/Main.elm --output dist/main.js`
    // `elm-optimize-level-2 src/Main.elm --output dist/main.js && terser dist/main.js  --module --compress 'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe' | terser --module --mangle --output=dist/main.js`
    // "cd ./elm-stuff/elm-pages && elm make ../../src/Main.elm --output elm.js"
  );
  elmToEsm(path.join(process.cwd(), `./dist/main.js`));

  await shellCommand(
    `terser dist/main.js  --module --compress 'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe' | terser --module --mangle --output=dist/main.js`
    // "cd ./elm-stuff/elm-pages && elm make ../../src/Main.elm --output elm.js"
  );
  fs.copyFileSync("./index.js", "dist/index.js");
}

async function compileCliApp() {
  await shellCommand(
    `cd ./elm-stuff/elm-pages && elm-optimize-level-2 ../../src/Main.elm --output elm.js`
  );
  const elmFileContent = fs.readFileSync(ELM_FILE_PATH, "utf-8");
  fs.writeFileSync(
    ELM_FILE_PATH,
    elmFileContent.replace(
      /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
      "return x"
    )
  );
}

run();

/**
 * @param {string} command
 */
async function shellCommand(command) {
  const output = await exec(command);
  if (output.stderr) {
    throw output.stderr;
  }
  // console.log(output.stdout);
  return output;
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

function wrapHtml(/** @type { FromElm } */ fromElm) {
  /*html*/
  return `<!DOCTYPE html>
  <html lang="en">
  <head>
    <link rel="preload" href="content.json" as="fetch" crossorigin="">
    <base href="${baseRoute(fromElm.route)}">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <script>if ("serviceWorker" in navigator) {
      window.addEventListener("load", () => {
        navigator.serviceWorker.register("service-worker.js");
      });
    } else {
      console.log("No service worker registered.");
    }</script>
    <link rel="shortcut icon" href="assets/favicon.ico">
    <link rel="icon" type="image/png" sizes="16x16" href="assets/favicon-16x16.png">
    <link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="48x48" href="assets/favicon-48x48.png">
    <link rel="manifest" href="assets/manifest.json">
    <meta name="mobile-web-app-capable" content="yes"><meta name="theme-color" content="#ffffff"><meta name="application-name" content="elm-pages docs"><link rel="apple-touch-icon" sizes="57x57" href="assets/apple-touch-icon-57x57.png"><link rel="apple-touch-icon" sizes="60x60" href="assets/apple-touch-icon-60x60.png"><link rel="apple-touch-icon" sizes="72x72" href="assets/apple-touch-icon-72x72.png"><link rel="apple-touch-icon" sizes="76x76" href="assets/apple-touch-icon-76x76.png"><link rel="apple-touch-icon" sizes="114x114" href="assets/apple-touch-icon-114x114.png"><link rel="apple-touch-icon" sizes="120x120" href="assets/apple-touch-icon-120x120.png"><link rel="apple-touch-icon" sizes="144x144" href="assets/apple-touch-icon-144x144.png"><link rel="apple-touch-icon" sizes="152x152" href="assets/apple-touch-icon-152x152.png"><link rel="apple-touch-icon" sizes="167x167" href="assets/apple-touch-icon-167x167.png"><link rel="apple-touch-icon" sizes="180x180" href="assets/apple-touch-icon-180x180.png"><link rel="apple-touch-icon" sizes="1024x1024" href="assets/apple-touch-icon-1024x1024.png"><meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">

    <meta name="apple-mobile-web-app-title" content="elm-pages">
    <script defer="defer" src="/main.js" type="module"></script>
    <script defer="defer" src="/index.js" type="module"></script>
    <link rel="preload" href="/main.js" as="script">
    ${seo.toString(fromElm.head)}
    <body>
      ${fromElm.html}
    </body>
  </html>
  `;
}
